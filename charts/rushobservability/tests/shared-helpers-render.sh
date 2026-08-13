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
  rg -q --fixed-strings "$expected" <<<"$inherited_image" || {
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
  rg -q --fixed-strings "$expected" <<<"$overridden_image" || {
    echo "anomaly engine image override was not honored: $expected" >&2
    exit 1
  }
done

rendered="$(helm template shared-helpers "$chart_dir" \
  --set collectors.mode=hybrid \
  --set collectors.allowAnonymousIngest=true \
  --set sreAgent.enabled=true \
  --set sreAgent.networkPolicy.allowExternalHttpsEgress=true \
  --set sreAgent.llmApiKeySecret.name=llm-key \
  --set enterprise.license.integrations.postgresCollector.enabled=true \
  --set-json 'enterprise.license.integrations.postgresCollector.networkPolicy.extraEgress=[{"to":[{"ipBlock":{"cidr":"10.0.0.0/8"}}],"ports":[{"protocol":"TCP","port":5432}]}]' \
  --set queryApi.baseUrl=https://rush.example.com \
  --set queryApi.service.port=18080)"

if [[ "$(rg -c --fixed-strings 'value: "http://shared-helpers-query-api:18080"' <<<"$rendered")" -lt 2 ]]; then
  echo 'internal consumers did not consistently use the query-api Service port' >&2
  exit 1
fi

for collector_template in \
  templates/otel-collector-workload.yaml \
  templates/vector-daemonset.yaml; do
  collector="$(helm template shared-helpers "$chart_dir" \
    --show-only "$collector_template" \
    --set collectors.mode=hybrid \
    --set collectors.allowAnonymousIngest=true)"
  if rg -q 'CLICKHOUSE_(USER|PASSWORD)' <<<"$collector"; then
    echo "$collector_template still receives unused ClickHouse credentials" >&2
    exit 1
  fi
done

echo 'shared Helm helper renders passed'
