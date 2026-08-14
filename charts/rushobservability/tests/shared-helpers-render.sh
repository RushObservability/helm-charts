#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
digest='sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

inherited_image="$(helm template shared-helpers "$chart_dir" \
  --show-only templates/anomaly-engine-deployment.yaml \
  --set anomalyEngine.enabled=true \
  --set queryApi.image.repository=example.test/rush \
  --set queryApi.image.tag=1.2.3 \
  --set queryApi.image.pullPolicy=IfNotPresent)"
for expected in \
  'image: "example.test/rush:1.2.3"' \
  'imagePullPolicy: IfNotPresent'; do
  grep -Fq "$expected" <<<"$inherited_image" || {
    echo "anomaly engine did not inherit query-api image field: $expected" >&2
    exit 1
  }
done

# The inherited digest also satisfies the chart-wide immutable-image policy.
helm template shared-helpers "$chart_dir" \
  --set anomalyEngine.enabled=true \
  --set imageSecurity.requireDigests=true \
  --set queryApi.image.digest="$digest" \
  --set frontend.image.digest="$digest" >/dev/null

overridden_image="$(helm template shared-helpers "$chart_dir" \
  --show-only templates/anomaly-engine-deployment.yaml \
  --set anomalyEngine.enabled=true \
  --set queryApi.image.repository=example.test/rush \
  --set queryApi.image.tag=1.2.3 \
  --set anomalyEngine.image.repository=example.test/anomaly \
  --set anomalyEngine.image.tag=9.8.7 \
  --set anomalyEngine.image.pullPolicy=Never)"
for expected in \
  'image: "example.test/anomaly:9.8.7"' \
  'imagePullPolicy: Never'; do
  grep -Fq "$expected" <<<"$overridden_image" || {
    echo "anomaly engine image override was not honored: $expected" >&2
    exit 1
  }
done

echo 'shared Helm helper renders passed'
