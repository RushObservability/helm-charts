#!/usr/bin/env bash
set -euo pipefail
chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_value() { grep -A1 "name: $1\$" | sed -n 's/^ *value: //p'; }

rendered="$(helm template health "$chart_dir")"
[ "$(env_value METRICS_AGENT_SCRAPE_ALLOWED_TARGET_NAMESPACES <<<"$rendered")" = '"*"' ] \
  || { echo 'default must scrape every Prometheus and VM object (target namespaces "*")' >&2; exit 1; }
if grep -q 'METRICS_AGENT_SCRAPE_ALLOWED_NAMESPACES$' <<<"$rendered"; then
  echo 'empty allowedNamespaces must not render an env var' >&2; exit 1
fi

rendered="$(helm template health "$chart_dir" --set 'scrape.allowedNamespaces={monitoring,apps}' --set 'scrape.allowedTargetNamespaces=null')"
[ "$(env_value METRICS_AGENT_SCRAPE_ALLOWED_NAMESPACES <<<"$rendered")" = '"monitoring,apps"' ] \
  || { echo 'allowedNamespaces must render comma-separated' >&2; exit 1; }
if grep -q 'METRICS_AGENT_SCRAPE_ALLOWED_TARGET_NAMESPACES$' <<<"$rendered"; then
  echo 'cleared allowedTargetNamespaces must not render an env var' >&2; exit 1
fi

if helm template health "$chart_dir" --set 'scrape.allowedTargetNamespaces={Bad_NS}' >/dev/null 2>&1; then
  echo 'schema must reject invalid namespace names' >&2; exit 1
fi
echo 'scrape namespace renders passed'
