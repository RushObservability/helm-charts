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
  rg -q --fixed-strings "$expected" <<<"$rendered" || {
    echo "operational-control render missing: $expected" >&2
    exit 1
  }
done

without_startup="$(helm template controls "$chart_dir" \
  --show-only templates/frontend-deployment.yaml \
  --set frontend.probes.startup.enabled=false)"
if rg -q --fixed-strings 'startupProbe:' <<<"$without_startup"; then
  echo 'disabled frontend startup probe was still rendered' >&2
  exit 1
fi

daemonset="$(helm template controls "$chart_dir" \
  --show-only templates/otel-collector-workload.yaml \
  --set collectors.mode=otel \
  --set collectors.allowAnonymousIngest=true \
  --set collectors.otel.kind=daemonset)"
if rg -q '^  strategy:' <<<"$daemonset"; then
  echo 'Deployment rollout strategy leaked into the OTel DaemonSet' >&2
  exit 1
fi
for expected in 'updateStrategy:' 'maxSurge: 1' 'startupProbe:'; do
  rg -q --fixed-strings "$expected" <<<"$daemonset" || {
    echo "OTel DaemonSet control missing: $expected" >&2
    exit 1
  }
done

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
  rg -q --fixed-strings "$expected" <<<"$standalone" || {
    echo "standalone ClickHouse control missing: $expected" >&2
    exit 1
  }
done

echo 'rollout, PDB, and probe Helm renders passed'
