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
assert_rejected 'the removed top-level SRE agent block' --set sreAgent.enabled=true
assert_rejected 'an invalid image digest' --set queryApi.image.digest=sha256:nope
assert_rejected 'a zero probe timeout' --set queryApi.probes.readiness.timeoutSeconds=0
assert_rejected 'an unknown rollout strategy' --set frontend.rollout.strategy=BlueGreen
assert_rejected 'an invalid PDB type' --set frontend.podDisruptionBudget.type=both
assert_rejected 'an invalid Ingress path type' --set ingress.frontend.pathType=Sometimes
assert_rejected 'a malformed image pull secret' --set-json 'queryApi.imagePullSecrets=[{}]'
assert_rejected 'a malformed extra volume mount' --set-json 'frontend.extraVolumeMounts=[{"name":"data"}]'
assert_rejected 'a negative Helm test deadline' --set helmTests.activeDeadlineSeconds=-1

echo 'values schema validation passed'
