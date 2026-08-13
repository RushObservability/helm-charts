#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$chart_dir/tests/fixtures/scheduling-values.yaml"

query_api="$(helm template scheduling "$chart_dir" \
  --show-only templates/query-api-deployment.yaml -f "$fixture")"
for expected in \
  'nodegroup: query-api' \
  'topology-zone: west' \
  'key: rush-apps' \
  'nodeAffinity:' \
  'topologySpreadConstraints:'; do
  grep -Fq "$expected" <<<"$query_api" || {
    echo "query-api scheduling merge is missing: $expected" >&2
    exit 1
  }
done

frontend="$(helm template scheduling "$chart_dir" \
  --show-only templates/frontend-deployment.yaml -f "$fixture")"
grep -Fq 'nodegroup: frontend-only' <<<"$frontend" || {
  echo 'frontend scheduling override was not rendered' >&2
  exit 1
}
for inherited in 'topology-zone: west' 'key: rush-apps' 'nodeAffinity:' 'topologySpreadConstraints:'; do
  if grep -Fq "$inherited" <<<"$frontend"; then
    echo "inheritGlobalScheduling=false retained global value: $inherited" >&2
    exit 1
  fi
done

otel="$(helm template scheduling "$chart_dir" \
  --show-only templates/otel-collector-workload.yaml -f "$fixture")"
for expected in 'nodegroup: rush-apps' 'key: otel-only' 'nodeAffinity:' 'topologySpreadConstraints:'; do
  grep -Fq "$expected" <<<"$otel" || {
    echo "OTel scheduling merge is missing: $expected" >&2
    exit 1
  }
done
if grep -Fq 'key: rush-apps' <<<"$otel"; then
  echo 'component tolerations did not replace the global tolerations list' >&2
  exit 1
fi

for workload_template in \
  templates/sre-agent-deployment.yaml \
  templates/anomaly-engine-deployment.yaml \
  templates/vector-daemonset.yaml \
  templates/postgres-collector-deployment.yaml; do
  workload="$(helm template scheduling "$chart_dir" \
    --show-only "$workload_template" -f "$fixture")"
  grep -Fq 'nodegroup: rush-apps' <<<"$workload" || {
    echo "$workload_template did not inherit global scheduling" >&2
    exit 1
  }
done

operator_clickhouse="$(helm template scheduling "$chart_dir" \
  --show-only charts/clickhouse/templates/chi.yaml -f "$fixture")"
grep -Fq 'nodegroup: clickhouse' <<<"$operator_clickhouse" || {
  echo 'operator-managed ClickHouse did not render its independent node selector' >&2
  exit 1
}
if grep -Fq 'nodegroup: rush-apps' <<<"$operator_clickhouse"; then
  echo 'operator-managed ClickHouse inherited Rush workload scheduling' >&2
  exit 1
fi

keeper="$(helm template scheduling "$chart_dir" \
  --show-only charts/clickhouse/templates/chk.yaml -f "$fixture")"
grep -Fq 'key: nodegroup' <<<"$keeper" && \
  grep -Fq '"clickhouse"' <<<"$keeper" || {
  echo 'Keeper did not render its independent node selector' >&2
  exit 1
}
if grep -Fq '"rush-apps"' <<<"$keeper"; then
  echo 'Keeper inherited Rush workload scheduling' >&2
  exit 1
fi

clickhouse_operator="$(helm template scheduling "$chart_dir" \
  --show-only charts/clickhouse/charts/operator/templates/generated/Deployment-clickhouse-operator.yaml \
  -f "$fixture")"
grep -Fq 'nodegroup: rush-apps' <<<"$clickhouse_operator" || {
  echo 'ClickHouse operator scheduling override was not rendered' >&2
  exit 1
}

crd_hook="$(helm template scheduling "$chart_dir" \
  --show-only charts/clickhouse/charts/operator/templates/hooks/crd-install-job.yaml \
  -f "$fixture")"
grep -Fq 'nodegroup: rush-apps' <<<"$crd_hook" || {
  echo 'ClickHouse CRD hook scheduling override was not rendered' >&2
  exit 1
}

standalone_clickhouse="$(helm template scheduling "$chart_dir" \
  --show-only templates/clickhouse-standalone-statefulset.yaml \
  --set queryApi.environment=development \
  --set clickhouse.mode=standalone \
  --set clickhouse.enabled=false \
  --set-string global.scheduling.nodeSelector.nodegroup=rush-apps \
  --set-string clickhouseStandalone.nodeSelector.nodegroup=clickhouse)"
grep -Fq 'nodegroup: clickhouse' <<<"$standalone_clickhouse" || {
  echo 'standalone ClickHouse node selector was not rendered' >&2
  exit 1
}
if grep -Fq 'nodegroup: rush-apps' <<<"$standalone_clickhouse"; then
  echo 'standalone ClickHouse inherited Rush workload scheduling' >&2
  exit 1
fi

echo 'workload scheduling Helm renders passed'
