#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

rendered="$(helm template image-policy "$chart_dir" --set queryApi.environment=development)"
if rg -n 'image:[[:space:]]+"?[^[:space:]\"]*:latest("|[[:space:]]|$)|image:[[:space:]]+"?[^[:space:]\"]*:latest-' <<<"$rendered"; then
  echo 'rendered chart contains a floating latest image' >&2
  exit 1
fi

if helm template image-policy "$chart_dir" \
  --set queryApi.environment=development \
  --set queryApi.image.tag=latest >/dev/null 2>&1; then
  echo 'chart accepted queryApi.image.tag=latest' >&2
  exit 1
fi

digest_render="$(helm template image-policy "$chart_dir" \
  --show-only templates/query-api-deployment.yaml \
  --set queryApi.environment=development \
  --set queryApi.image.digest="$digest")"
if ! rg -q --fixed-strings "image: \"mzupan/rush-api@$digest\"" <<<"$digest_render"; then
  echo 'query-api digest did not take precedence over its tag' >&2
  exit 1
fi

if helm template image-policy "$chart_dir" \
  --set queryApi.environment=development \
  --set imageSecurity.requireDigests=true >/dev/null 2>&1; then
  echo 'digest-required policy accepted tag-only first-party images' >&2
  exit 1
fi

helm template image-policy "$chart_dir" \
  --set queryApi.environment=development \
  --set imageSecurity.requireDigests=true \
  --set queryApi.image.digest="$digest" \
  --set frontend.image.digest="$digest" >/dev/null

echo 'image security Helm renders passed'
