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

defaults="$(helm template secure-ingest "$chart_dir")"
assert_render "$defaults" 'name: RUSH_ENVIRONMENT' 'environment posture variable'
assert_render "$defaults" 'value: "production"' 'fail-closed production default'
assert_render "$defaults" 'name: RUSH_ALLOW_ANONYMOUS_DEFAULT' 'anonymous compatibility variable'
assert_render "$defaults" 'value: "false"' 'anonymous compatibility disabled by default'

if helm template secure-ingest "$chart_dir" --set collectors.mode=otel >/dev/null 2>&1; then
  echo 'collector rendered without an ingest API-key Secret' >&2
  exit 1
fi

anonymous="$(helm template secure-ingest "$chart_dir" \
  --set collectors.mode=otel \
  --set collectors.allowAnonymousIngest=true)"
if grep -Fq 'name: RUSH_INGEST_API_KEY' <<<"$anonymous"; then
  echo 'anonymous collector unexpectedly references an ingest-key Secret' >&2
  exit 1
fi

collector="$(helm template secure-ingest "$chart_dir" \
  --set collectors.mode=otel \
  --set collectors.ingestApiKeySecret.name=rush-collector-ingest)"
assert_render "$collector" 'name: RUSH_INGEST_API_KEY' 'collector ingest-key environment variable'
assert_render "$collector" 'name: rush-collector-ingest' 'collector ingest-key Secret reference'
assert_render "$collector" 'Authorization: "Bearer ${env:RUSH_INGEST_API_KEY}"' 'OTel Bearer header'

vector="$(helm template secure-ingest "$chart_dir" \
  --set collectors.mode=vector \
  --set collectors.ingestApiKeySecret.name=rush-collector-ingest)"
assert_render "$vector" 'name: RUSH_INGEST_API_KEY' 'Vector ingest-key environment variable'
assert_render "$vector" 'Authorization: "Bearer ${RUSH_INGEST_API_KEY}"' 'Vector Bearer header'

development="$(helm template secure-ingest "$chart_dir" \
  --set queryApi.environment=development \
  --set queryApi.allowAnonymousDefault=true)"
assert_render "$development" 'value: "development"' 'explicit development environment'
assert_render "$development" 'value: "true"' 'explicit anonymous compatibility override'

echo 'secure-ingest Helm renders passed'
