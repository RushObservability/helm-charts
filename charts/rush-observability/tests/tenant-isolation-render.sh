#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_render() {
  local rendered="$1"
  local pattern="$2"
  local description="$3"
  if ! grep -Fq "$pattern" <<<"$rendered"; then
    echo "missing ${description}: ${pattern}" >&2
    return 1
  fi
}

operator="$(helm template tenant-policy "$chart_dir")"
assert_render "$operator" '<custom_settings_prefixes>rush_</custom_settings_prefixes>' 'operator custom setting'
assert_render "$operator" 'rushquery/grants/query:' 'operator read-only principal'
assert_render "$operator" 'GRANT SELECT ON observability.logs' 'operator telemetry grant'
assert_render "$operator" 'name: CLICKHOUSE_READ_USER' 'query-api read identity'
assert_render "$operator" 'path: /readyz' 'fail-closed readiness endpoint'

standalone="$(helm template tenant-policy "$chart_dir" \
  --set clickhouse.enabled=false \
  --set clickhouse.mode=standalone)"
assert_render "$standalone" '<custom_settings_prefixes>rush_</custom_settings_prefixes>' 'standalone custom setting'
assert_render "$standalone" '<rushquery>' 'standalone read-only principal'
assert_render "$standalone" 'RUSH_CLICKHOUSE_READ_PASSWORD' 'standalone read credential injection'

external="$(helm template tenant-policy "$chart_dir" \
  --set clickhouse.enabled=false \
  --set clickhouse.mode=external \
  --set queryApi.networkPolicy.allowExternalClickHouseEgress=true \
  --set clickhouse.external.url=https://clickhouse.example:8443 \
  --set clickhouse.external.credentialsSecret=clickhouse-writer \
  --set clickhouse.external.readCredentialsSecret=clickhouse-reader)"
assert_render "$external" 'name: clickhouse-reader' 'external read credential Secret'

echo 'tenant-isolation Helm renders passed'
