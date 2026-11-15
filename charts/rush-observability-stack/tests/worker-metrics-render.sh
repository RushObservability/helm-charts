#!/usr/bin/env bash
set -euo pipefail
chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
render_dir="$(mktemp -d)"
trap 'rm -rf "$render_dir"' EXIT
helm template health "$chart_dir" --namespace rush-health --set rush.anomalyEngine.enabled=true > "$render_dir/enabled.yaml"
helm template health "$chart_dir" --namespace rush-health --set rush.anomalyEngine.enabled=true --set selfMonitoring.workerScrapes=false > "$render_dir/disabled.yaml"
helm template health "$chart_dir" --set rush.anomalyEngine.enabled=true --set metricsAgent.enabled=false > "$render_dir/no-agent.yaml"
python3 - "$render_dir" <<'PY'
import pathlib
import sys
import yaml

root = pathlib.Path(sys.argv[1])
for filename in ['enabled.yaml', 'disabled.yaml', 'no-agent.yaml']:
    docs = [doc for doc in yaml.safe_load_all((root / filename).read_text()) if doc]
    scrapes = [doc for doc in docs if doc['kind'] == 'VMServiceScrape' and doc['metadata']['name'].endswith('-worker-metrics')]
    if filename != 'enabled.yaml':
        assert not scrapes
        continue
    assert len(scrapes) == 1
    spec = scrapes[0]['spec']
    assert spec['namespaceSelector']['matchNames'] == ['rush-health']
    assert spec['endpoints'][0]['port'] == 'metrics'
    selector = spec['selector']['matchLabels']
    selected = [doc for doc in docs if doc['kind'] == 'Service' and all(doc['metadata']['labels'].get(key) == value for key, value in selector.items())]
    assert selected and all(doc['metadata']['labels']['app.kubernetes.io/component'] == 'anomaly-engine' for doc in selected)
    # query-api self-ingests its registry; scraping it again would duplicate it.
    assert not any(doc['metadata']['labels']['app.kubernetes.io/component'] == 'query-api' for doc in selected)
PY
echo 'stack worker metrics discovery renders correctly'
