#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rendered="$(helm template controls "$chart_dir" \
  --set queryApi.replicas=2 \
  --set clickhouse.keeper.enabled=true \
  --set queryApi.buffer.backend=object_store \
  --set queryApi.networkPolicy.allowExternalHttpsEgress=true \
  --set queryApi.buffer.objectStore.bucket=rush-buffer \
  --set queryApi.buffer.objectStore.credentialsSecret.name=rush-buffer \
  --set queryApi.buffer.drainWorker.enabled=true \
  --set queryApi.podDisruptionBudget.enabled=true \
  --set queryApi.podDisruptionBudget.type=minAvailable \
  --set queryApi.podDisruptionBudget.value=1 \
  --set queryApi.rollout.maxSurge=25% \
  --set queryApi.probes.startup.failureThreshold=42)"

for expected in \
  'kind: PodDisruptionBudget' \
  'name: controls-query-api-pdb' \
  'minAvailable: 1' \
  'maxSurge: 25%' \
  'startupProbe:' \
  'failureThreshold: 42'; do
  grep -Fq "$expected" <<<"$rendered" || {
    echo "operational-control render missing: $expected" >&2
    exit 1
  }
done

without_startup="$(helm template controls "$chart_dir" \
  --show-only templates/frontend-deployment.yaml \
  --set frontend.probes.startup.enabled=false)"
if grep -Fq 'startupProbe:' <<<"$without_startup"; then
  echo 'disabled frontend startup probe was still rendered' >&2
  exit 1
fi

standalone="$(helm template controls "$chart_dir" \
  --set clickhouse.enabled=false \
  --set clickhouse.mode=standalone \
  --set clickhouseStandalone.podDisruptionBudget.enabled=true)"
for expected in \
  'kind: StatefulSet' \
  'podManagementPolicy: OrderedReady' \
  'partition: 0' \
  'name: controls-clickhouse-pdb' \
  'path: /ping'; do
  grep -Fq "$expected" <<<"$standalone" || {
    echo "standalone ClickHouse control missing: $expected" >&2
    exit 1
  }
done

echo 'rollout, PDB, and probe Helm renders passed'
