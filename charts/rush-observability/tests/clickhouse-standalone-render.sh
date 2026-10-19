#!/usr/bin/env bash
set -euo pipefail

# Standalone ClickHouse must use the same clickhouse.clickhouse sizing and cache
# settings as operator mode. It used to read keys that don't exist, which left
# the pod without resources and every server cache at 0.
chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
standalone=(--set clickhouse.mode=standalone --set clickhouse.enabled=false)

statefulset="$(helm template ch "$chart_dir" "${standalone[@]}" \
  --show-only templates/clickhouse-standalone-statefulset.yaml)"
for expected in 'memory: 8Gi' 'cpu: 500m'; do
  grep -Fq "$expected" <<<"$statefulset" || {
    echo "standalone ClickHouse resources are missing: $expected" >&2
    exit 1
  }
done
if grep -A1 -E '^ +resources:$' <<<"$statefulset" | grep -Eq '^ +null$'; then
  echo 'standalone ClickHouse rendered resources: null' >&2
  exit 1
fi

config="$(helm template ch "$chart_dir" "${standalone[@]}" \
  --set clickhouse.clickhouse.logLevel=debug \
  --show-only templates/clickhouse-standalone-configmap.yaml)"
for expected in \
  '<mark_cache_size>2147483648</mark_cache_size>' \
  '<uncompressed_cache_size>134217728</uncompressed_cache_size>' \
  '<text_index_postings_cache_size>1073741824</text_index_postings_cache_size>' \
  '<level>debug</level>'; do
  grep -Fq "$expected" <<<"$config" || {
    echo "standalone ClickHouse config is missing: $expected" >&2
    exit 1
  }
done

# The old clickhouse.resources key still wins when set.
legacy="$(helm template ch "$chart_dir" "${standalone[@]}" \
  --set clickhouse.resources.limits.memory=16Gi \
  --show-only templates/clickhouse-standalone-statefulset.yaml)"
grep -Fq 'memory: 16Gi' <<<"$legacy" || {
  echo 'clickhouse.resources override was ignored' >&2
  exit 1
}
if grep -Fq 'memory: 8Gi' <<<"$legacy"; then
  echo 'clickhouse.resources override was merged with the default' >&2
  exit 1
fi
