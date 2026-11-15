#!/usr/bin/env bash
set -euo pipefail
chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
render_dir="$(mktemp -d)"
trap 'rm -rf "$render_dir"' EXIT
# Use the same supported object-store deployment as the HA buffer tests.
ha=(--set queryApi.workloadKind=StatefulSet --set queryApi.replicas=3
  --set clickhouse.keeper.enabled=true --set queryApi.config.ingest.buffer.backend=object_store
  --set queryApi.networkPolicy.allowExternalHttpsEgress=true
  --set queryApi.config.ingest.buffer.objectStore.endpoint=https://s3.example.test
  --set queryApi.config.ingest.buffer.objectStore.bucket=rush-buffer
  --set queryApi.config.ingest.buffer.objectStore.credentialsSecret.name=rush-buffer
  --set queryApi.drainWorker.enabled=true)
helm template health "$chart_dir" "${ha[@]}" --set anomalyEngine.enabled=true > "$render_dir/enabled.yaml"
helm template health "$chart_dir" "${ha[@]}" --set anomalyEngine.enabled=true --set workerMetrics.enabled=false > "$render_dir/disabled.yaml"
helm template health "$chart_dir" "${ha[@]}" --set anomalyEngine.enabled=true --set workerMetrics.port=9191 > "$render_dir/custom.yaml"
python3 - "$render_dir" <<'PY'
import pathlib
import sys
import yaml

root = pathlib.Path(sys.argv[1])
for filename, port in [('enabled.yaml', 9090), ('custom.yaml', 9191), ('disabled.yaml', None)]:
    docs = [doc for doc in yaml.safe_load_all((root / filename).read_text()) if doc]
    for component in ['query-api-drain-worker', 'anomaly-engine']:
        deployment = next(doc for doc in docs if doc['kind'] == 'Deployment' and doc['metadata']['labels'].get('app.kubernetes.io/component') == component)
        container = deployment['spec']['template']['spec']['containers'][0]
        env = {entry['name']: entry.get('value') for entry in container['env']}
        assert env['RUSH_WORKER_METRICS_ADDR'] == (f'0.0.0.0:{port}' if port else '')
        services = [doc for doc in docs if doc['kind'] == 'Service' and doc['metadata']['labels'].get('app.kubernetes.io/component') == component]
        policies = [doc for doc in docs if doc['kind'] == 'NetworkPolicy' and doc['metadata']['name'].endswith('-metrics') and doc['metadata']['labels'].get('app.kubernetes.io/component') == component]
        if port:
            assert container['ports'] == [{'name': 'metrics', 'containerPort': port}]
            assert len(services) == 1 and len(policies) == 1
            assert services[0]['spec']['selector'] == deployment['spec']['selector']['matchLabels']
            assert services[0]['spec']['ports'] == [{'name': 'metrics', 'port': port, 'targetPort': 'metrics'}]
            ingress = policies[0]['spec']['ingress'][0]
            assert ingress['ports'] == [{'protocol': 'TCP', 'port': 'metrics'}]
            assert ingress['from'][0]['podSelector']['matchLabels'] == {'app.kubernetes.io/component': 'metrics-agent', 'app.kubernetes.io/instance': 'health'}
        else:
            assert not services and not policies and not container.get('ports')
PY
echo 'worker metrics listeners, services, and network paths render correctly'
