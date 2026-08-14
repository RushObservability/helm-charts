#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_has() {
  local rendered="$1"
  local pattern="$2"
  local description="$3"
  if ! grep -Fq "$pattern" <<<"$rendered"; then
    echo "missing ${description}: ${pattern}" >&2
    return 1
  fi
}

assert_lacks() {
  local rendered="$1"
  local pattern="$2"
  local description="$3"
  if grep -Fq "$pattern" <<<"$rendered"; then
    echo "unexpected ${description}: ${pattern}" >&2
    return 1
  fi
}

argocd="$(helm template infra "$chart_dir" --show-only templates/argocd-rbac.yaml \
  --set argocd.enabled=true)"
assert_has "$argocd" 'kind: Role' 'namespace-scoped ArgoCD Role'
assert_has "$argocd" 'apiGroups: ["argoproj.io"]' 'ArgoCD API group'
assert_lacks "$argocd" 'kind: ClusterRole' 'ArgoCD ClusterRole'
assert_lacks "$argocd" 'apiGroups: [""]' 'ArgoCD core API permissions'
assert_lacks "$argocd" 'secrets' 'ArgoCD Secret permission'

flux="$(helm template infra "$chart_dir" --show-only templates/fluxcd-rbac.yaml \
  --set fluxcd.enabled=true)"
assert_has "$flux" 'kind: Role' 'namespace-scoped Flux Role'
assert_has "$flux" 'apiGroups: ["source.toolkit.fluxcd.io"]' 'Flux API group'
assert_lacks "$flux" 'kind: ClusterRole' 'Flux ClusterRole'
assert_lacks "$flux" 'apiGroups: [""]' 'Flux core API permissions'
assert_lacks "$flux" 'secrets' 'Flux Secret permission'

kubernetes="$(helm template infra "$chart_dir" --show-only templates/kubernetes-rbac.yaml \
  --set kubernetes.enabled=true \
  --set 'kubernetes.namespaces[0]=apps')"
assert_has "$kubernetes" 'kind: Role' 'namespace-scoped Kubernetes Role'
assert_lacks "$kubernetes" 'kind: ClusterRole' 'default Kubernetes ClusterRole'
assert_lacks "$kubernetes" 'secrets' 'Kubernetes Secret permission'

cluster="$(helm template infra "$chart_dir" --show-only templates/kubernetes-rbac.yaml \
  --set kubernetes.enabled=true \
  --set kubernetes.clusterWide=true)"
assert_has "$cluster" 'kind: ClusterRole' 'opt-in Kubernetes ClusterRole'
assert_lacks "$cluster" 'secrets' 'cluster-wide Kubernetes Secret permission'

if helm template infra "$chart_dir" --show-only templates/kubernetes-rbac.yaml \
  --set kubernetes.enabled=true >/dev/null 2>&1; then
  echo 'kubernetes integration rendered without namespaces or clusterWide opt-in' >&2
  exit 1
fi

network_policy="$(helm template infra "$chart_dir" --show-only templates/query-api-networkpolicy.yaml)"
assert_has "$network_policy" 'policyTypes: [Ingress, Egress]' 'query-api ingress and egress policy'

deployment="$(helm template infra "$chart_dir" --show-only templates/query-api-deployment.yaml \
  --set 'infrastructure.tenantNamespaces.acme[0]=acme-prod')"
assert_has "$deployment" 'name: RUSH_INFRASTRUCTURE_TENANT_NAMESPACES' 'tenant namespace policy env'
assert_has "$deployment" '{\"acme\":[\"acme-prod\"]}' 'serialized tenant namespace policy'
assert_has "$deployment" 'automountServiceAccountToken: false' 'disabled Kubernetes token by default'

echo 'infrastructure security Helm renders passed'
