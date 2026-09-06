#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_contains() {
  local rendered="$1"
  local pattern="$2"
  local description="$3"
  if ! grep -Fq "$pattern" <<<"$rendered"; then
    echo "missing ${description}: ${pattern}" >&2
    exit 1
  fi
}

assert_absent() {
  local rendered="$1"
  local pattern="$2"
  local description="$3"
  if grep -Fq "$pattern" <<<"$rendered"; then
    echo "unexpected ${description}: ${pattern}" >&2
    exit 1
  fi
}

assert_count() {
  local rendered="$1"
  local pattern="$2"
  local expected="$3"
  local description="$4"
  local actual
  actual="$(grep -Fc "$pattern" <<<"$rendered")"
  if [[ "$actual" != "$expected" ]]; then
    echo "wrong ${description}: expected ${expected}, got ${actual}: ${pattern}" >&2
    exit 1
  fi
}

defaults="$(helm template kubernetes-access "$chart_dir")"
assert_absent "$defaults" 'name: KUBERNETES_ACCESS_ENABLED' 'default Kubernetes access env'
assert_absent "$defaults" 'app.kubernetes.io/component: kubernetes-access-gateway' 'default gateway workload'
assert_contains "$defaults" 'kubernetes-access-internal-token:' 'preserved recorder token'

enabled="$(helm template kubernetes-access "$chart_dir" \
  --set enterprise.license.enabled=true \
  --set queryApi.integrations.kubernetesAccess.enabled=true \
  --set queryApi.integrations.kubernetesAccess.maxResultBytes=524288 \
  --set queryApi.integrations.kubernetesAccess.maxSessionBytes=134217728 \
  --set queryApi.integrations.kubernetesAccess.retentionDays=14 \
  --set queryApi.integrations.kubernetesAccess.credentialTtlSeconds=7200 \
  --set kubernetesAccessGateway.gatewayId=primary \
  --set kubernetesAccessGateway.clusterId=prod-us-east-1 \
  --set kubernetesAccessGateway.tenantIds[0]=default)"

assert_contains "$enabled" 'name: KUBERNETES_ACCESS_ENABLED' 'feature flag'
assert_contains "$enabled" 'name: KUBERNETES_ACCESS_INTERNAL_TOKEN' 'recorder token reference'
assert_contains "$enabled" 'key: kubernetes-access-internal-token' 'recorder token key'
assert_contains "$enabled" 'name: KUBERNETES_ACCESS_MAX_RESULT_BYTES' 'result byte limit'
assert_contains "$enabled" 'value: "524288"' 'configured result byte limit'
assert_contains "$enabled" 'name: KUBERNETES_ACCESS_MAX_SESSION_BYTES' 'session byte limit'
assert_contains "$enabled" 'value: "134217728"' 'configured session byte limit'
assert_contains "$enabled" 'name: KUBERNETES_ACCESS_RETENTION_DAYS' 'retention policy'
assert_contains "$enabled" 'value: "14"' 'configured retention days'
assert_contains "$enabled" 'name: KUBERNETES_ACCESS_RETAIN_RAW_IP' 'raw IP policy'
assert_contains "$enabled" 'value: "false"' 'privacy-safe default'
assert_contains "$enabled" 'name: KUBERNETES_ACCESS_GATEWAY_ID' 'stable gateway binding'
assert_contains "$enabled" 'value: "primary"' 'stable gateway ID'
assert_contains "$enabled" 'name: KUBERNETES_ACCESS_GATEWAY_TENANT_IDS' 'gateway tenant binding'
assert_contains "$enabled" 'value: "default"' 'configured gateway tenant'
assert_contains "$enabled" 'name: KUBERNETES_ACCESS_TENANT_CLUSTERS' 'tenant-to-cluster policy'
assert_contains "$enabled" 'value: "{\"default\":[\"prod-us-east-1\"]}"' 'derived tenant-to-cluster policy'
assert_contains "$enabled" 'name: KUBERNETES_ACCESS_CREDENTIAL_TTL_SECONDS' 'temporary credential lifetime'
assert_contains "$enabled" 'value: "7200"' 'configured temporary credential lifetime'
assert_absent "$enabled" 'KUBERNETES_ACCESS_API_KEY_IDS' 'Kubernetes API key allowlist'
assert_absent "$enabled" 'KUBERNETES_ACCESS_API_KEY_ROLES' 'Kubernetes API key role mapping'

gateway="$(helm template kubernetes-access "$chart_dir" \
  --set enterprise.license.enabled=true \
  --set kubernetesAccessGateway.enabled=true \
  --set kubernetesAccessGateway.gatewayId=primary \
  --set kubernetesAccessGateway.clusterId=prod-us-east-1 \
  --set kubernetesAccessGateway.tenantIds[0]=default \
  --set kubernetesAccessGateway.serviceAccount.create=false \
  --set kubernetesAccessGateway.serviceAccount.name=rush-kube-proxy)"

assert_contains "$gateway" 'app.kubernetes.io/component: kubernetes-access-gateway' 'gateway workload'
assert_contains "$gateway" 'name: KUBE_UPSTREAM_BEARER_TOKEN_FILE' 'projected service-account token'
assert_contains "$gateway" 'name: RUSH_GATEWAY_INTERNAL_TOKEN' 'internal recorder credential'
assert_contains "$gateway" 'name: RUSH_GATEWAY_ID' 'logical gateway identity'
assert_contains "$gateway" 'name: RUSH_GATEWAY_MANAGE_RBAC' 'RBAC reconciliation flag'
assert_contains "$gateway" 'value: "primary"' 'logical gateway binding'
assert_contains "$gateway" 'name: RUSH_GATEWAY_RETAIN_RAW_IP' 'gateway raw IP retention policy'
assert_count "$gateway" 'name: RUSH_GATEWAY_RETAIN_RAW_IP' 1 'gateway raw IP retention env count'
assert_count "$gateway" 'name: KUBERNETES_ACCESS_RETAIN_RAW_IP' 1 'query-api raw IP retention env count'
assert_contains "$gateway" 'value: "prod-us-east-1"' 'cluster binding'
assert_contains "$gateway" 'name: KUBERNETES_ACCESS_ENABLED' 'query-api recording feature'
assert_contains "$gateway" 'kind: NetworkPolicy' 'gateway network policy'
assert_absent "$gateway" 'resources: ["users", "groups"]' 'implicit impersonation grant'

external_secret="$(helm template kubernetes-access "$chart_dir" \
  --set enterprise.license.enabled=true \
  --set queryApi.existingSecret=operator-bootstrap \
  --set kubernetesAccessGateway.enabled=true \
  --set kubernetesAccessGateway.gatewayId=primary \
  --set kubernetesAccessGateway.clusterId=prod-us-east-1 \
  --set kubernetesAccessGateway.tenantIds[0]=default \
  --set kubernetesAccessGateway.serviceAccount.create=false \
  --set kubernetesAccessGateway.serviceAccount.name=rush-kube-proxy)"
assert_contains "$external_secret" 'name: operator-bootstrap' 'existing bootstrap Secret reference'
assert_contains "$external_secret" 'key: kubernetes-access-internal-token' 'existing Secret recorder key'

if helm template kubernetes-access "$chart_dir" \
  --set kubernetesAccessGateway.enabled=true \
  --set kubernetesAccessGateway.gatewayId=primary \
  --set kubernetesAccessGateway.clusterId=prod \
  --set kubernetesAccessGateway.tenantIds[0]=default >/dev/null 2>&1; then
  echo 'gateway rendered without an enterprise license' >&2
  exit 1
fi

if helm template kubernetes-access "$chart_dir" \
  --set enterprise.license.enabled=true \
  --set kubernetesAccessGateway.enabled=true \
  --set kubernetesAccessGateway.gatewayId=primary \
  --set kubernetesAccessGateway.clusterId=prod \
  --set kubernetesAccessGateway.tenantIds[0]=default >/dev/null 2>&1; then
  echo 'gateway rendered without an existing service account or explicit impersonation role' >&2
  exit 1
fi

generated_rbac="$(helm template kubernetes-access "$chart_dir" \
  --set enterprise.license.enabled=true \
  --set kubernetesAccessGateway.enabled=true \
  --set kubernetesAccessGateway.gatewayId=primary \
  --set kubernetesAccessGateway.clusterId=prod \
  --set kubernetesAccessGateway.tenantIds[0]=default \
  --set kubernetesAccessGateway.rbac.createImpersonationRole=true)"
assert_contains "$generated_rbac" 'resources: ["users", "groups"]' 'explicit impersonation grant'
assert_contains "$generated_rbac" 'verbs: ["impersonate"]' 'impersonation verb'
assert_absent "$generated_rbac" '"bind", "escalate"' 'implicit RBAC management grant'

managed_rbac="$(helm template kubernetes-access "$chart_dir" \
  --set enterprise.license.enabled=true \
  --set kubernetesAccessGateway.enabled=true \
  --set kubernetesAccessGateway.gatewayId=primary \
  --set kubernetesAccessGateway.clusterId=prod \
  --set kubernetesAccessGateway.tenantIds[0]=default \
  --set kubernetesAccessGateway.rbac.manageRoles=true)"
assert_contains "$managed_rbac" 'name: RUSH_GATEWAY_MANAGE_RBAC' 'managed RBAC environment flag'
assert_contains "$managed_rbac" 'value: "true"' 'enabled RBAC reconciliation'
assert_contains "$managed_rbac" 'resources: ["clusterroles"]' 'ClusterRole reconciliation grant'
assert_contains "$managed_rbac" '"bind", "escalate"' 'binding and custom role permissions'
assert_contains "$managed_rbac" 'resources: ["clusterrolebindings", "rolebindings"]' 'binding reconciliation grant'

if helm template kubernetes-access "$chart_dir" \
  --set enterprise.license.enabled=true \
  --set kubernetesAccessGateway.enabled=true \
  --set kubernetesAccessGateway.gatewayId=primary \
  --set kubernetesAccessGateway.tenantIds[0]=default \
  --set kubernetesAccessGateway.rbac.createImpersonationRole=true >/dev/null 2>&1; then
  echo 'gateway rendered without a cluster ID' >&2
  exit 1
fi

if helm template kubernetes-access "$chart_dir" \
  --set enterprise.license.enabled=true \
  --set kubernetesAccessGateway.enabled=true \
  --set kubernetesAccessGateway.gatewayId=primary \
  --set kubernetesAccessGateway.clusterId=prod \
  --set kubernetesAccessGateway.rbac.createImpersonationRole=true >/dev/null 2>&1; then
  echo 'gateway rendered without an explicit tenant binding' >&2
  exit 1
fi

if helm template kubernetes-access "$chart_dir" \
  --set enterprise.license.enabled=true \
  --set kubernetesAccessGateway.enabled=true \
  --set kubernetesAccessGateway.clusterId=prod \
  --set kubernetesAccessGateway.tenantIds[0]=default \
  --set kubernetesAccessGateway.rbac.createImpersonationRole=true >/dev/null 2>&1; then
  echo 'gateway rendered without a stable gateway ID' >&2
  exit 1
fi

if helm template kubernetes-access "$chart_dir" \
  --set queryApi.integrations.kubernetesAccess.retentionDays=0 >/dev/null 2>&1; then
  echo 'chart accepted zero-day Kubernetes access retention' >&2
  exit 1
fi

echo 'Kubernetes access recording Helm renders passed'
