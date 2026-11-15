#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rendered="$(helm template frontend-security "$chart_dir" --set queryApi.config.runtime.environment=production --set queryApi.config.runtime.baseUrl=https://rush.example.com --set clickhouse.keeper.enabled=true)"

if grep -q 'Content-Security-Policy' <<<"$rendered"; then
  echo 'Helm must not duplicate the CSP policy baked into the frontend image' >&2
  exit 1
fi
for required in \
  'include /etc/nginx/security-headers.conf;' \
  'readOnlyRootFilesystem: true' \
  'runAsNonRoot: true' \
  'runAsUser: 65532' \
  'allowPrivilegeEscalation: false' \
  'mountPath: /tmp' \
  'name: RUSH_ENVIRONMENT' \
  'value: "production"'; do
  if ! grep -Fq "$required" <<<"$rendered"; then
    echo "rendered frontend security policy is missing: $required" >&2
    exit 1
  fi
done

# query-api's /metrics is unauthenticated; the UI must not publish it by default.
if grep -Fq 'location = /metrics' <<<"$rendered"; then
  echo 'frontend proxies the unauthenticated query-api /metrics by default' >&2
  exit 1
fi
grep -Fq 'wget -q -T 10 -O /dev/null "${QUERY_API_URL}/metrics"' <<<"$rendered" || {
  echo 'helm test must scrape query-api /metrics directly' >&2
  exit 1
}
grep -Fq 'location = /metrics' <<<"$(helm template frontend-security "$chart_dir" --set frontend.proxyQueryApiMetrics=true)" || {
  echo 'frontend.proxyQueryApiMetrics=true did not proxy /metrics' >&2
  exit 1
}

notes="$(<"$chart_dir/templates/NOTES.txt")"
grep -q 'Strict-Transport-Security' <<<"$notes" || {
  echo 'production install notes must document HSTS at the TLS terminator' >&2
  exit 1
}

echo 'frontend nginx and runtime security Helm renders passed'
