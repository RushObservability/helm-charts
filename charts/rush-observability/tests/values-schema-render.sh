#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

helm lint "$chart_dir" >/dev/null

assert_rejected() {
  local description="$1"
  shift
  if helm template schema "$chart_dir" "$@" >/dev/null 2>&1; then
    echo "values schema accepted ${description}" >&2
    exit 1
  fi
}

assert_rejected 'zero API replicas' --set queryApi.replicas=0
assert_rejected 'the removed collectors block' --set collectors.mode=otel
assert_rejected 'the old global SRE agent block' --set global.sreAgent.enabled=true
assert_rejected 'the old top-level SRE agent block' --set sreAgent.enabled=true
assert_rejected 'the old top-level Kubernetes integration block' --set kubernetes.enabled=true
assert_rejected 'the old Query API Kubernetes access block' --set queryApi.kubernetesAccess.enabled=true
assert_rejected 'the old Query API runtime path' --set queryApi.environment=development
assert_rejected 'the old Query API secret path' --set queryApi.existingSecret=rush-bootstrap
assert_rejected 'the old Query API authentication path' --set queryApi.ssoReplayStore=local
assert_rejected 'the old Query API ingest path' --set queryApi.buffer.backend=disk
assert_rejected 'the old Query API integration path' --set queryApi.config.integrations.argocd.enabled=true
assert_rejected 'the old top-level PromQL path' --set promql.lookbackSecs=120
assert_rejected 'the old rushConfig root' --set rushConfig.retention.defaults.metrics_days=30
assert_rejected 'a snake_case retention key' --set queryApi.config.retention.defaults.metrics_days=30
assert_rejected 'a zero-day retention rule' --set queryApi.config.retention.metrics[0].name=requests --set queryApi.config.retention.metrics[0].retainDays=0
assert_rejected 'an unknown Query API config group' --set queryApi.config.runtim.environment=development
assert_rejected 'an unknown Query API integration' --set queryApi.integrations.kuberentes.enabled=true
assert_rejected 'a zero-second PromQL lookback' --set queryApi.config.promql.lookbackSecs=0
assert_rejected 'standalone ClickHouse with the operator dependency enabled' --set clickhouse.mode=standalone
assert_rejected 'operator ClickHouse with the dependency disabled' --set clickhouse.mode=operator --set clickhouse.enabled=false
assert_rejected 'production mode without a public URL' --set queryApi.config.runtime.environment=production --set queryApi.config.runtime.baseUrl=
assert_rejected 'an invalid image digest' --set queryApi.image.digest=sha256:nope
assert_rejected 'a zero probe timeout' --set queryApi.probes.readiness.timeoutSeconds=0
assert_rejected 'an unknown rollout strategy' --set frontend.rollout.strategy=BlueGreen
assert_rejected 'an invalid PDB type' --set frontend.podDisruptionBudget.type=both
assert_rejected 'an invalid Ingress path type' --set ingress.frontend.pathType=Sometimes
assert_rejected 'a malformed image pull secret' --set-json 'queryApi.imagePullSecrets=[{}]'
assert_rejected 'a malformed extra volume mount' --set-json 'frontend.extraVolumeMounts=[{"name":"data"}]'
assert_rejected 'a negative Helm test deadline' --set helmTests.activeDeadlineSeconds=-1
assert_rejected 'a short Kubernetes access token' --set queryApi.integrations.kubernetesAccess.internalToken=short
assert_rejected 'an undersized Kubernetes result limit' --set queryApi.integrations.kubernetesAccess.maxResultBytes=512
assert_rejected 'an oversized Kubernetes session limit' --set queryApi.integrations.kubernetesAccess.maxSessionBytes=2147483648

retention="$(helm template schema "$chart_dir" \
  --show-only templates/rush-config-configmap.yaml \
  --set queryApi.config.retention.defaults.metricsDays=45 \
  --set-string 'queryApi.config.retention.metrics[0].nameRegex=http_.*' \
  --set-string 'queryApi.config.retention.metrics[0].labels.environment=prod' \
  --set 'queryApi.config.retention.metrics[0].retainDays=90' \
  --set-string 'queryApi.config.retention.traces[0].serviceName=checkout' \
  --set 'queryApi.config.retention.traces[0].retainDays=120' \
  --set queryApi.config.retention.enforcer.intervalSeconds=600 \
  --set queryApi.config.retention.enforcer.dryRun=true)"
for expected in \
  'metrics_days = 45' \
  'name_regex = "http_.*"' \
  'labels = {environment = "prod" }' \
  'retain_days = 90' \
  'service_name = "checkout"' \
  'retain_days = 120' \
  'interval_secs = 600' \
  'dry_run = true'; do
  grep -Fq "$expected" <<<"$retention" || {
    echo "retention config render is missing: $expected" >&2
    exit 1
  }
done

promql="$(helm template schema "$chart_dir" \
  --show-only templates/query-api-deployment.yaml \
  --set queryApi.config.promql.lookbackSecs=120)"
grep -Fq 'value: "120"' <<<"$promql" || {
  echo 'Query API PromQL lookback did not render from queryApi.config.promql' >&2
  exit 1
}

echo 'values schema validation passed'
