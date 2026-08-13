#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rendered="$(helm template frontend-security "$chart_dir" --set queryApi.environment=production --set queryApi.baseUrl=https://rush.example.com)"

if rg -q 'Content-Security-Policy' <<<"$rendered"; then
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
  if ! rg -q --fixed-strings "$required" <<<"$rendered"; then
    echo "rendered frontend security policy is missing: $required" >&2
    exit 1
  fi
done

notes="$(<"$chart_dir/templates/NOTES.txt")"
rg -q 'Strict-Transport-Security' <<<"$notes" || {
  echo 'production install notes must document HSTS at the TLS terminator' >&2
  exit 1
}

echo 'frontend nginx and runtime security Helm renders passed'
