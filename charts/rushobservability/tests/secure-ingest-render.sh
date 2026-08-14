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

development="$(helm template secure-ingest "$chart_dir" \
  --set queryApi.environment=development \
  --set queryApi.allowAnonymousDefault=true)"
assert_render "$development" 'value: "development"' 'explicit development environment'
assert_render "$development" 'value: "true"' 'explicit anonymous compatibility override'

echo 'core secure-default Helm renders passed'
