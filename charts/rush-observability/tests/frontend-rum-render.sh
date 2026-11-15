#!/usr/bin/env bash
set -euo pipefail
chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
render_dir="$(mktemp -d)"
trap 'rm -rf "$render_dir"' EXIT
helm template health "$chart_dir" --show-only templates/frontend-deployment.yaml > "$render_dir/default.yaml"
helm template health "$chart_dir" --show-only templates/frontend-deployment.yaml \
  --set frontend.rum.enabled=true --set frontend.rum.appName=rush-canary \
  --set frontend.rum.endpoint=/api/v1/rum/ingest > "$render_dir/enabled.yaml"
python3 - "$render_dir" <<'PY'
import pathlib
import sys
import yaml

root = pathlib.Path(sys.argv[1])
for filename, enabled, app in [('default.yaml', 'false', 'rush-ui'), ('enabled.yaml', 'true', 'rush-canary')]:
    deployment = yaml.safe_load((root / filename).read_text())
    env = {entry['name']: entry.get('value') for entry in deployment['spec']['template']['spec']['containers'][0]['env']}
    assert env['RUM_ENABLED'] == enabled, env
    assert env['RUM_ENDPOINT'] == '/api/v1/rum/ingest', env
    assert env['RUM_APP_NAME'] == app, env
    assert env['RUSH_ENVIRONMENT'] == 'development', env
PY
for endpoint in 'https://external.example/ingest' '//external.example/ingest' '/api/v1/rum/ingest?token=value'; do
  if helm template health "$chart_dir" --set-string "frontend.rum.endpoint=$endpoint" >/dev/null 2>&1; then
    echo 'RUM endpoint must be a same-origin path without query parameters' >&2
    exit 1
  fi
done
echo 'frontend RUM runtime configuration renders passed'
