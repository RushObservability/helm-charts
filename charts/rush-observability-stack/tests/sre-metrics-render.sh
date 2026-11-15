#!/usr/bin/env bash
set -euo pipefail
chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
render_dir="$(mktemp -d)"
trap 'rm -rf "$render_dir"' EXIT
enabled=(--set rush.queryApi.integrations.sreAgent.enabled=true --set metricsAgent.sreMetrics.enabled=true)
helm template health "$chart_dir" "${enabled[@]}" --set metricsAgent.networkPolicy.enabled=true --set-json 'metricsAgent.networkPolicy.egress=[]' > "$render_dir/enabled.yaml"
helm template health "$chart_dir" --set rush.queryApi.integrations.sreAgent.enabled=true > "$render_dir/disabled.yaml"
helm template health "$chart_dir" "${enabled[@]}" --set rush.queryApi.config.secrets.existingSecret=external-bootstrap \
  --set metricsAgent.sreMetrics.tokenSecret.name=external-bootstrap \
  --set rush.queryApi.integrations.sreAgent.service.port=8181 \
  --set metricsAgent.sreMetrics.url=http://health-sre-agent:8181/metrics > "$render_dir/custom.yaml"
python3 - "$render_dir" <<'PY'
import pathlib
import sys
import yaml

root = pathlib.Path(sys.argv[1])
for filename, expected_secret, port in [('enabled.yaml', 'health-bootstrap', 8081), ('custom.yaml', 'external-bootstrap', 8181), ('disabled.yaml', None, 8081)]:
    docs = [doc for doc in yaml.safe_load_all((root / filename).read_text()) if doc]
    deployment = next(doc for doc in docs if doc['kind'] == 'Deployment' and doc['metadata']['name'] == 'health-metrics-agent')
    pod = deployment['spec']['template']['spec']
    container = pod['containers'][0]
    env = {entry['name']: entry.get('value') for entry in container['env']}
    token_volumes = [volume for volume in pod.get('volumes', []) if volume['name'] == 'sre-metrics-token']
    if not expected_secret:
        assert not token_volumes and 'METRICS_AGENT_SRE_METRICS_URL' not in env
        continue
    assert env['METRICS_AGENT_SRE_METRICS_URL'] == f'http://health-sre-agent:{port}/metrics'
    assert env['METRICS_AGENT_SRE_METRICS_TOKEN_FILE'] == '/var/run/rush-sre-metrics/token'
    assert env['METRICS_AGENT_SRE_METRICS_SERVICE'] == 'health-sre-agent'
    raw_env = {entry['name']: entry for entry in container['env']}
    assert raw_env['METRICS_AGENT_SRE_METRICS_NAMESPACE']['valueFrom']['fieldRef']['fieldPath'] == 'metadata.namespace'
    assert token_volumes[0]['secret']['secretName'] == expected_secret
    assert token_volumes[0]['secret']['items'] == [{'key': 'sre-agent-internal-token', 'path': 'token'}]
    mounts = [mount for mount in container['volumeMounts'] if mount['name'] == 'sre-metrics-token']
    assert mounts == [{'name': 'sre-metrics-token', 'mountPath': '/var/run/rush-sre-metrics', 'readOnly': True}]
    sre_policy = next(doc for doc in docs if doc['kind'] == 'NetworkPolicy' and doc['metadata']['name'] == 'health-sre-agent')
    sources = sre_policy['spec']['ingress'][0]['from']
    assert any(source.get('podSelector', {}).get('matchLabels', {}).get('app.kubernetes.io/component') == 'metrics-agent' for source in sources)
    if filename == 'enabled.yaml':
        agent_policy = next(doc for doc in docs if doc['kind'] == 'NetworkPolicy' and doc['metadata']['name'] == 'health-metrics-agent')
        assert agent_policy['spec']['egress'][0]['ports'] == [{'protocol': 'TCP', 'port': 'http'}]
PY
assert_rejected() {
  if helm template health "$chart_dir" "$@" >/dev/null 2>&1; then
    echo 'unsupported authenticated scrape configuration was accepted' >&2
    exit 1
  fi
}
assert_rejected --set metricsAgent.sreMetrics.enabled=true
assert_rejected "${enabled[@]}" --set rush.queryApi.config.secrets.existingSecret=external-bootstrap
assert_rejected "${enabled[@]}" --set rush.queryApi.integrations.sreAgent.service.port=8181
assert_rejected "${enabled[@]}" --set metricsAgent.sreMetrics.url=http://user:token@health-sre-agent:8081/metrics
echo 'authenticated SRE metrics configuration and network paths render correctly'
