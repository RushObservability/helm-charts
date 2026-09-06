#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

rendered="$(helm template image-policy "$chart_dir" --set queryApi.config.runtime.environment=development)"
if grep -En 'image:[[:space:]]+"?[^[:space:]\"]*:latest("|[[:space:]]|$)|image:[[:space:]]+"?[^[:space:]\"]*:latest-' <<<"$rendered"; then
  echo 'rendered chart contains a floating latest image' >&2
  exit 1
fi

if helm template image-policy "$chart_dir" \
  --set queryApi.config.runtime.environment=development \
  --set queryApi.image.tag=latest >/dev/null 2>&1; then
  echo 'chart accepted queryApi.image.tag=latest' >&2
  exit 1
fi

digest_render="$(helm template image-policy "$chart_dir" \
  --show-only templates/query-api-deployment.yaml \
  --set queryApi.config.runtime.environment=development \
  --set queryApi.image.digest="$digest")"
if ! grep -Fq "image: \"mzupan/rush-api@$digest\"" <<<"$digest_render"; then
  echo 'query-api digest did not take precedence over its tag' >&2
  exit 1
fi

mirror_render="$(helm template image-policy "$chart_dir" \
  --set global.image.registry=mirror.example.com/cache \
  --set clickhouse.mode=standalone \
  --set clickhouse.enabled=false \
  --set anomalyEngine.enabled=true)"
for expected in \
  'image: "mirror.example.com/cache/mzupan/rush-api:0.1.25"' \
  'image: "mirror.example.com/cache/rushobservability/frontend:0.1.6"' \
  'image: "mirror.example.com/cache/clickhouse/clickhouse-server:26.6.1.1193"'; do
  grep -Fq "$expected" <<<"$mirror_render" || {
    echo "global image registry render is missing: $expected" >&2
    exit 1
  }
done

mirror_digest="$(helm template image-policy "$chart_dir" \
  --show-only templates/query-api-deployment.yaml \
  --set global.image.registry=mirror.example.com:5000/cache/ \
  --set queryApi.image.repository=source.example.com/team/query-api \
  --set queryApi.image.digest="$digest")"
grep -Fq "image: \"mirror.example.com:5000/cache/team/query-api@$digest\"" <<<"$mirror_digest" || {
  echo 'global registry did not replace the source registry or preserve the digest' >&2
  exit 1
}

if helm template image-policy "$chart_dir" \
  --set-string global.image.registry=https://mirror.example.com >/dev/null 2>&1; then
  echo 'chart accepted a global image registry with a URL scheme' >&2
  exit 1
fi

if helm template image-policy "$chart_dir" \
  --set queryApi.config.runtime.environment=development \
  --set imageSecurity.requireDigests=true >/dev/null 2>&1; then
  echo 'digest-required policy accepted tag-only first-party images' >&2
  exit 1
fi

helm template image-policy "$chart_dir" \
  --set queryApi.config.runtime.environment=development \
  --set imageSecurity.requireDigests=true \
  --set queryApi.image.digest="$digest" \
  --set frontend.image.digest="$digest" >/dev/null

echo 'image security Helm renders passed'
