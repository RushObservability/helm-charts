#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
core_chart_dir="$chart_dir/../rush-observability"
common=(--set rush.queryApi.environment=development)

if ! helm dependency list "$core_chart_dir" | awk 'NR > 1 && NF && $NF != "ok" { bad=1 } END { exit bad }'; then
  helm dependency build "$core_chart_dir" >/dev/null
fi
if ! helm dependency list "$chart_dir" | awk 'NR > 1 && NF && $NF != "ok" { bad=1 } END { exit bad }'; then
  helm dependency build "$chart_dir" >/dev/null
fi
helm lint "$chart_dir" >/dev/null
helm template stack-example "$chart_dir" \
  -f "$chart_dir/../../examples/rush-stack.yaml" \
  --set rush.queryApi.environment=development >/dev/null

defaults="$(helm template stack "$chart_dir" "${common[@]}")"
for core in stack-query-api stack-frontend; do
  grep -Fq "name: $core" <<<"$defaults" || {
    echo "default stack is missing core workload: $core" >&2
    exit 1
  }
done
for expected in \
  'name: stack-ingest' \
  'name: RUSH_BOOTSTRAP_INGEST_API_KEY' \
  'name: RUSH_API_KEY_SECRET' \
  'key: api-key-hmac-secret'; do
  grep -Fq "$expected" <<<"$defaults" || {
    echo "default stack automatic ingest bootstrap is missing: $expected" >&2
    exit 1
  }
done
for addon in 'name: stack-sre-agent' 'name: stack-postgres-collector' 'name: stack-mysql-collector'; do
  if grep -Fq "$addon" <<<"$defaults"; then
    echo "default stack unexpectedly installed opt-in add-on: $addon" >&2
    exit 1
  fi
done
for component in 'name: stack-otel-collector' 'name: stack-vector' 'name: stack-metrics-agent' 'name: stack-clickhouse-standalone'; do
  grep -Fq "$component" <<<"$defaults" || {
    echo "default stack is missing collection component: $component" >&2
    exit 1
  }
done
for expected in 'value: "development"' 'value: "http://localhost:8080"' 'value: "{\"env\":\"dev\"}"'; do
  grep -Fq "$expected" <<<"$defaults" || {
    echo "default development setting is missing: $expected" >&2
    exit 1
  }
done

if helm template stack "$chart_dir" --set rush-observability.queryApi.environment=development >/dev/null 2>&1; then
  echo 'the removed rush-observability values block was accepted; use rush instead' >&2
  exit 1
fi

if helm template stack "$chart_dir" "${common[@]}" \
  --set collectors.mode=otel \
  --set global.rush.ingestApiKeySecret.autoGenerate=false >/dev/null 2>&1; then
  echo 'collector rendered without an ingest-key Secret' >&2
  exit 1
fi

automatic_ingest="$(helm template stack "$chart_dir" "${common[@]}" \
  --set collectors.mode=otel \
  --set metricsAgent.enabled=true)"
for expected in \
  'name: stack-ingest' \
  'name: RUSH_INGEST_API_KEY' \
  'name: RUSH_BOOTSTRAP_INGEST_API_KEY' \
  'Authorization: "Bearer ${env:RUSH_INGEST_API_KEY}"'; do
  grep -Fq "$expected" <<<"$automatic_ingest" || {
    echo "automatic ingest-key render is missing: $expected" >&2
    exit 1
  }
done

inline_ingest="$(helm template stack "$chart_dir" "${common[@]}" \
  --set collectors.mode=otel \
  --set metricsAgent.enabled=true \
  --set-string global.rush.ingestApiKeySecret.value=rush_ing_test_install_0123456789abcdef0123456789abcdef)"
inline_ingest_encoded="$(printf %s rush_ing_test_install_0123456789abcdef0123456789abcdef | base64 | tr -d '\n')"
for expected in \
  'kind: Secret' \
  'name: stack-ingest' \
  "api-key: \"$inline_ingest_encoded\"" \
  'name: "stack-ingest"' \
  'name: RUSH_INGEST_API_KEY'; do
  grep -Fq "$expected" <<<"$inline_ingest" || {
    echo "install-time ingest Secret render is missing: $expected" >&2
    exit 1
  }
done

otel="$(helm template stack "$chart_dir" "${common[@]}" \
  --set collectors.mode=otel \
  --set global.rush.ingestApiKeySecret.name=rush-ingest)"
for expected in \
  'name: stack-otel-collector' \
  'name: RUSH_INGEST_API_KEY' \
  'name: rush-ingest' \
  'Authorization: "Bearer ${env:RUSH_INGEST_API_KEY}"' \
  'endpoint: http://stack-query-api:8080'; do
  grep -Fq "$expected" <<<"$otel" || {
    echo "OTel stack render is missing: $expected" >&2
    exit 1
  }
done

vector="$(helm template stack "$chart_dir" "${common[@]}" \
  --set collectors.mode=vector \
  --set collectors.vector.mode=full-otel \
  --set global.rush.ingestApiKeySecret.name=rush-ingest)"
for expected in 'kind: DaemonSet' 'name: stack-vector' 'Authorization: "Bearer ${RUSH_INGEST_API_KEY}"' 'containerPort: 4317'; do
  grep -Fq "$expected" <<<"$vector" || {
    echo "Vector stack render is missing: $expected" >&2
    exit 1
  }
done

metrics="$(helm template stack "$chart_dir" "${common[@]}" \
  --set metricsAgent.enabled=true \
  --set-string metricsAgent.extraLabels.env=dev \
  --set global.rush.ingestApiKeySecret.name=rush-ingest)"
for expected in \
  'value: "http://stack-query-api:8080/prom/api/v1/write"' \
  'name: "rush-ingest"' \
  'value: "{\"env\":\"dev\"}"' \
  'app.kubernetes.io/component: metrics-agent'; do
  grep -Fq "$expected" <<<"$metrics" || {
    echo "metrics-agent stack render is missing: $expected" >&2
    exit 1
  }
done

sre="$(helm template stack "$chart_dir" "${common[@]}" \
  --set rush.queryApi.integrations.sreAgent.enabled=true)"
for expected in 'name: stack-sre-agent' 'value: "http://stack-query-api:8080"' 'name: SRE_AGENT_INTERNAL_TOKEN'; do
  grep -Fq "$expected" <<<"$sre" || {
    echo "SRE-agent stack render is missing: $expected" >&2
    exit 1
  }
done
if grep -Eq 'OPENAI_API_KEY|CLICKHOUSE_URL' <<<"$(sed -n '/name: stack-sre-agent/,/---/p' <<<"$sre")"; then
  echo "SRE-agent must not receive provider or ClickHouse credentials" >&2
  exit 1
fi

if helm template stack "$chart_dir" "${common[@]}" \
  --set rush.sreAgent.enabled=true >/dev/null 2>&1; then
  echo 'the removed rush.sreAgent block was accepted; use rush.queryApi.integrations.sreAgent' >&2
  exit 1
fi
if helm template stack "$chart_dir" "${common[@]}" \
  --set rush.queryApi.kubernetesAccess.enabled=true >/dev/null 2>&1; then
  echo 'the removed rush.queryApi.kubernetesAccess block was accepted; use rush.queryApi.integrations.kubernetesAccess' >&2
  exit 1
fi

integrations="$(helm template stack "$chart_dir" "${common[@]}" \
  --set rush.queryApi.integrations.argocd.enabled=true \
  --set rush.queryApi.integrations.fluxcd.enabled=true \
  --set rush.queryApi.integrations.kubernetes.enabled=true \
  --set 'rush.queryApi.integrations.kubernetes.namespaces[0]=apps' \
  --set rush.queryApi.integrations.cloudwatch.enabled=true)"
for expected in 'name: ARGOCD_NAMESPACE' 'name: FLUXCD_NAMESPACE' 'name: KUBERNETES_ENABLED' 'name: CLOUDWATCH_ENABLED'; do
  grep -Fq "$expected" <<<"$integrations" || {
    echo "stack integration render is missing: $expected" >&2
    exit 1
  }
done

postgres="$(helm template stack "$chart_dir" "${common[@]}" \
  --set postgresCollector.enabled=true \
  --set rush.enterprise.license.enabled=true \
  --set-json 'postgresCollector.networkPolicy.extraEgress=[{"to":[{"ipBlock":{"cidr":"10.0.0.0/8"}}],"ports":[{"protocol":"TCP","port":5432}]}]')"
for expected in 'name: stack-postgres-collector' 'name: RUSH_LICENSE_KEY' 'value: "http://stack-query-api:8080"'; do
  grep -Fq "$expected" <<<"$postgres" || {
    echo "Postgres stack render is missing: $expected" >&2
    exit 1
  }
done

mysql="$(helm template stack "$chart_dir" "${common[@]}" \
  --set mysqlCollector.enabled=true \
  --set rush.enterprise.license.enabled=true \
  --set-json 'mysqlCollector.networkPolicy.extraEgress=[{"to":[{"ipBlock":{"cidr":"10.0.0.0/8"}}],"ports":[{"protocol":"TCP","port":3306}]}]')"
for expected in 'name: stack-mysql-collector' 'name: MYSQL_DSN' 'name: RUSH_LICENSE_KEY' 'value: "http://stack-query-api:8080"'; do
  grep -Fq "$expected" <<<"$mysql" || {
    echo "MySQL stack render is missing: $expected" >&2
    exit 1
  }
done

if helm template stack "$chart_dir" "${common[@]}" --set collectors.mode=unknown >/dev/null 2>&1; then
  echo 'stack schema accepted an unknown collector mode' >&2
  exit 1
fi
if helm template stack "$chart_dir" "${common[@]}" \
  --kube-version 1.26.0 \
  --set metricsAgent.enabled=true \
  --set global.rush.ingestApiKeySecret.name=rush-ingest >/dev/null 2>&1; then
  echo 'metrics-agent rendered on an unsupported Kubernetes version' >&2
  exit 1
fi

echo 'rush-observability-stack renders passed'
