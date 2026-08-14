#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rendered="$(helm template audit-test "$chart_dir" --set queryApi.baseUrl=https://rush.example.com)"

for expected in \
  'name: RUSH_AUDIT_HMAC_KEY_ID' \
  'name: RUSH_AUDIT_HMAC_PREVIOUS_KEYS' \
  'name: RUSH_SESSION_HMAC_SECRET' \
  'name: RUSH_AUDIT_SPOOL_DIR' \
  'name: RUSH_AUDIT_SPOOL_MAX_BYTES' \
  'kind: PersistentVolumeClaim' \
  'claimName: audit-test-query-api-audit'
do
  if ! grep -Fq "$expected" <<<"$rendered"; then
    echo "missing secure audit render: $expected" >&2
    exit 1
  fi
done

ephemeral="$(helm template audit-test "$chart_dir" \
  --set queryApi.baseUrl=https://rush.example.com \
  --set queryApi.audit.spool.persistence.enabled=false)"
if grep -Fq 'kind: PersistentVolumeClaim' <<<"$ephemeral"; then
  echo "audit PVC rendered while persistence was disabled" >&2
  exit 1
fi
if ! grep -A2 -F 'name: audit-spool' <<<"$ephemeral" | grep -Fq 'emptyDir:'; then
  echo "ephemeral audit spool did not render an emptyDir" >&2
  exit 1
fi

echo "audit/session security Helm renders passed"
