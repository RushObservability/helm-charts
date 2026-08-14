#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
core_chart_dir="$chart_dir/../rush-observability"
common=(--set rush-observability.queryApi.environment=development)

if ! helm dependency list "$core_chart_dir" | awk 'NR > 1 && NF && $NF != "ok" { bad=1 } END { exit bad }'; then
  helm dependency build "$core_chart_dir" >/dev/null
fi
if ! helm dependency list "$chart_dir" | awk 'NR > 1 && NF && $NF != "ok" { bad=1 } END { exit bad }'; then
  helm dependency build "$chart_dir" >/dev/null
fi
helm lint "$chart_dir" >/dev/null
helm template stack-example "$chart_dir" \
  -f "$chart_dir/../../examples/rush-stack.yaml" \
  --set rush-observability.queryApi.environment=development >/dev/null

defaults="$(helm template stack "$chart_dir" "${common[@]}")"
for core in stack-query-api stack-frontend; do
  grep -Fq "name: $core" <<<"$defaults" || {
    echo "default stack is missing core workload: $core" >&2
    exit 1
  }
done
for addon in 'name: stack-otel-collector' 'name: stack-vector' 'name: stack-sre-agent' 'name: stack-postgres-collector' 'name: stack-metrics-agent'; do
  if grep -Fq "$addon" <<<"$defaults"; then
    echo "default stack unexpectedly installed opt-in add-on: $addon" >&2
    exit 1
  fi
done

if helm template stack "$chart_dir" "${common[@]}" --set collectors.mode=otel >/dev/null 2>&1; then
  echo 'collector rendered without an ingest-key Secret' >&2
  exit 1
fi

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
  --set global.sreAgent.enabled=true \
  --set global.sreAgent.llmApiKeySecret.name=openai \
  --set global.sreAgent.networkPolicy.allowExternalHttpsEgress=true)"
for expected in 'name: stack-sre-agent' 'value: "http://stack-query-api:8080"' 'name: openai'; do
  grep -Fq "$expected" <<<"$sre" || {
    echo "SRE-agent stack render is missing: $expected" >&2
    exit 1
  }
done

postgres="$(helm template stack "$chart_dir" "${common[@]}" \
  --set postgresCollector.enabled=true \
  --set rush-observability.enterprise.license.enabled=true \
  --set-json 'postgresCollector.networkPolicy.extraEgress=[{"to":[{"ipBlock":{"cidr":"10.0.0.0/8"}}],"ports":[{"protocol":"TCP","port":5432}]}]')"
for expected in 'name: stack-postgres-collector' 'name: RUSH_LICENSE_KEY' 'value: "http://stack-query-api:8080"'; do
  grep -Fq "$expected" <<<"$postgres" || {
    echo "Postgres stack render is missing: $expected" >&2
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
