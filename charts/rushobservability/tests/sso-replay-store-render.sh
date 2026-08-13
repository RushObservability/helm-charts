#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_render() {
  local rendered="$1"
  local pattern="$2"
  local description="$3"
  if ! grep -Fq "$pattern" <<<"$rendered"; then
    echo "missing ${description}: ${pattern}" >&2
    exit 1
  fi
}

defaults="$(helm template sso-replay "$chart_dir")"
assert_render "$defaults" 'name: RUSH_QUERY_API_REPLICAS' 'replica contract variable'
assert_render "$defaults" 'name: RUSH_SSO_REPLAY_STORE' 'SSO replay-store variable'
assert_render "$defaults" 'value: "auto"' 'automatic store selection'
assert_render "$defaults" '<keeper_map_path_prefix>/rush</keeper_map_path_prefix>' 'KeeperMap path prefix'

if helm template sso-replay "$chart_dir" --set queryApi.replicas=2 >/dev/null 2>&1; then
  echo 'multi-replica query-api rendered without ClickHouse Keeper' >&2
  exit 1
fi

ha="$(helm template sso-replay "$chart_dir" \
  --set queryApi.replicas=2 \
  --set clickhouse.keeper.enabled=true \
  --set queryApi.buffer.backend=object_store \
  --set queryApi.networkPolicy.allowExternalHttpsEgress=true \
  --set queryApi.buffer.objectStore.bucket=rush-buffer \
  --set queryApi.buffer.objectStore.credentialsSecret.name=rush-buffer \
  --set queryApi.buffer.drainWorker.enabled=true)"
assert_render "$ha" 'replicas: 2' 'HA query-api deployment'
assert_render "$ha" 'name: RUSH_SSO_REPLAY_STORE' 'HA replay-store variable'

if helm template sso-replay "$chart_dir" \
  --set queryApi.replicas=2 \
  --set clickhouse.keeper.enabled=true \
  --set queryApi.buffer.backend=object_store \
  --set queryApi.networkPolicy.allowExternalHttpsEgress=true \
  --set queryApi.buffer.objectStore.bucket=rush-buffer \
  --set queryApi.buffer.objectStore.credentialsSecret.name=rush-buffer \
  --set queryApi.buffer.drainWorker.enabled=true \
  --set queryApi.ssoReplayStore=local >/dev/null 2>&1; then
  echo 'multi-replica query-api accepted the process-local replay store' >&2
  exit 1
fi

if helm template sso-replay "$chart_dir" \
  --set queryApi.replicas=2 \
  --set clickhouse.enabled=false \
  --set clickhouse.mode=standalone >/dev/null 2>&1; then
  echo 'multi-replica query-api accepted standalone ClickHouse without Keeper' >&2
  exit 1
fi

echo 'SSO replay-store Helm renders passed'
