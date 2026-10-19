#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# query-api writes temporary files at runtime and exits with "Read-only file
# system" without a writable /tmp. Both workloads that run the binary keep a
# read-only root filesystem and get a size-limited emptyDir at /tmp instead.
assert_runtime_tmp() {
  local rendered="$1"
  local workload="$2"
  for expected in 'readOnlyRootFilesystem: true' 'mountPath: /tmp' 'name: runtime-tmp' 'sizeLimit: 256Mi'; do
    grep -Fq "$expected" <<<"$rendered" || {
      echo "${workload} render missing: ${expected}" >&2
      exit 1
    }
  done
}

query_api="$(helm template runtime "$chart_dir" --show-only templates/query-api-deployment.yaml)"
assert_runtime_tmp "$query_api" 'query-api'

worker="$(helm template runtime "$chart_dir" \
  --show-only templates/query-api-drain-worker-deployment.yaml \
  --set queryApi.workloadKind=StatefulSet \
  --set queryApi.replicas=3 \
  --set clickhouse.keeper.enabled=true \
  --set queryApi.config.ingest.buffer.backend=object_store \
  --set queryApi.networkPolicy.allowExternalHttpsEgress=true \
  --set queryApi.config.ingest.buffer.objectStore.bucket=rush-buffer \
  --set queryApi.config.ingest.buffer.objectStore.credentialsSecret.name=rush-buffer \
  --set queryApi.drainWorker.enabled=true)"
assert_runtime_tmp "$worker" 'query-api drain worker'

echo 'query-api runtime renders passed'
