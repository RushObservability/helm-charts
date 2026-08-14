#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if helm template ha-buffer "$chart_dir" \
  --set queryApi.replicas=2 \
  --set clickhouse.keeper.enabled=true >/dev/null 2>&1; then
  echo 'multi-replica query-api accepted a pod-local disk buffer' >&2
  exit 1
fi

if helm template ha-buffer "$chart_dir" \
  --set queryApi.buffer.backend=object_store \
  --set queryApi.buffer.objectStore.bucket=rush-buffer >/dev/null 2>&1; then
  echo 'object-store buffering accepted a missing credentials Secret' >&2
  exit 1
fi

if helm template ha-buffer "$chart_dir" \
  --set queryApi.buffer.drainWorker.enabled=true >/dev/null 2>&1; then
  echo 'the dedicated drain worker accepted a disk buffer' >&2
  exit 1
fi

rendered="$(helm template ha-buffer "$chart_dir" \
  --set queryApi.replicas=3 \
  --set clickhouse.keeper.enabled=true \
  --set queryApi.buffer.backend=object_store \
  --set queryApi.networkPolicy.allowExternalHttpsEgress=true \
  --set queryApi.buffer.objectStore.endpoint=https://s3.example.test \
  --set queryApi.buffer.objectStore.bucket=rush-buffer \
  --set queryApi.buffer.objectStore.credentialsSecret.name=rush-buffer \
  --set queryApi.buffer.drainWorker.enabled=true)"

for expected in \
  'name: ha-buffer-query-api-drain-worker' \
  'name: RUSH_DRAIN_WORKER_ONLY' \
  'value: "object_store"' \
  'name: rush-buffer' \
  'value: "2147483648"'; do
  grep -Fq "$expected" <<<"$rendered" || {
    echo "HA buffer render missing: $expected" >&2
    exit 1
  }
done

worker="$(helm template ha-buffer "$chart_dir" \
  --show-only templates/query-api-drain-worker-deployment.yaml \
  --set queryApi.replicas=3 \
  --set clickhouse.keeper.enabled=true \
  --set queryApi.buffer.backend=object_store \
  --set queryApi.networkPolicy.allowExternalHttpsEgress=true \
  --set queryApi.buffer.objectStore.bucket=rush-buffer \
  --set queryApi.buffer.objectStore.credentialsSecret.name=rush-buffer \
  --set queryApi.buffer.drainWorker.enabled=true)"
for expected in 'replicas: 1' 'type: Recreate' 'value: "true"'; do
  grep -Fq "$expected" <<<"$worker" || {
    echo "drain worker contract missing: $expected" >&2
    exit 1
  }
done

api="$(helm template ha-buffer "$chart_dir" \
  --show-only templates/query-api-deployment.yaml \
  --set queryApi.replicas=3 \
  --set clickhouse.keeper.enabled=true \
  --set queryApi.buffer.backend=object_store \
  --set queryApi.networkPolicy.allowExternalHttpsEgress=true \
  --set queryApi.buffer.objectStore.bucket=rush-buffer \
  --set queryApi.buffer.objectStore.credentialsSecret.name=rush-buffer \
  --set queryApi.buffer.drainWorker.enabled=true)"
grep -Fq 'name: RUSH_RUN_REPLAYER' <<<"$api"
grep -Fq 'value: "false"' <<<"$api"
if grep -Fq 'name: RUSH_DRAIN_WORKER_ONLY' <<<"$api"; then
  echo 'API pods were incorrectly rendered as drain-only workers' >&2
  exit 1
fi

echo 'HA ingest-buffer Helm renders passed'
