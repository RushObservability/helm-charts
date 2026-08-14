#!/usr/bin/env bash
set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
default_render="$(helm template remaining "$chart_dir")"
for expected in \
  'name: remaining-frontend' \
  'name: remaining-query-api' \
  'helm.sh/hook: test' \
  'name: remaining-connectivity-test'; do
  grep -Fq "$expected" <<<"$default_render" || {
    echo "default chart missing remaining-improvement resource: $expected" >&2
    exit 1
  }
done

query_policy="$(helm template remaining "$chart_dir" --show-only templates/query-api-networkpolicy.yaml)"
if grep -Fq 'cidr: 0.0.0.0/0' <<<"$query_policy"; then
  echo 'query-api still receives broad external egress by default' >&2
  exit 1
fi
for peer in frontend helm-test; do
  grep -Fq "app.kubernetes.io/component: $peer" <<<"$query_policy" || {
    echo "query-api NetworkPolicy is missing the $peer peer" >&2
    exit 1
  }
done

components="$(helm template remaining "$chart_dir" --set anomalyEngine.enabled=true)"
for component in frontend query-api anomaly-engine; do
  grep -Fq "name: remaining-$component" <<<"$components" || {
    echo "enabled core component is missing resources/policy: $component" >&2
    exit 1
  }
done

ingress="$(helm template remaining "$chart_dir" \
  --set ingress.enabled=true \
  --set ingress.className=nginx \
  --set ingress.frontend.host=rush.example.test \
  --set ingress.frontend.tls.secretName=rush-tls \
  --set ingress.api.enabled=true \
  --set ingress.api.host=api.rush.example.test \
  --set ingress.api.tls.secretName=rush-api-tls \
  --set ingress.trustedProxyCidrs[0]=10.42.0.0/16)"
for expected in \
  'kind: Ingress' \
  'ingressClassName: "nginx"' \
  'host: "rush.example.test"' \
  'host: "api.rush.example.test"' \
  'value: "https://rush.example.test"' \
  'value: "10.42.0.0/16"'; do
  grep -Fq "$expected" <<<"$ingress" || {
    echo "Ingress render missing: $expected" >&2
    exit 1
  }
done

if helm template remaining "$chart_dir" \
  --set ingress.enabled=true \
  --set ingress.frontend.host=rush.example.test \
  --set ingress.api.enabled=true \
  --set ingress.api.host=rush.example.test >/dev/null 2>&1; then
  echo 'Ingress accepted colliding frontend and API hosts' >&2
  exit 1
fi

if helm template remaining "$chart_dir" \
  --set ingress.enabled=true \
  --set ingress.frontend.host=rush.example.test \
  --set ingress.frontend.tls.enabled=false >/dev/null 2>&1; then
  echo 'production Ingress accepted an automatically derived HTTP base URL' >&2
  exit 1
fi

operational="$(helm template remaining "$chart_dir" \
  -f "$chart_dir/tests/fixtures/operational-values.yaml")"
for expected in \
  'example.com/global-annotation: shared' \
  'example.com/query-annotation: api' \
  'example.com/global-label: shared' \
  'example.com/query-label: api' \
  'name: registry-credentials' \
  'priorityClassName: "rush-critical"' \
  'runtimeClassName: "gvisor"' \
  'name: shared-runtime' \
  'mountPath: /etc/rush/shared-ca' \
  'name: custom-frontend' \
  'example.com/frontend-identity: ui'; do
  grep -Fq "$expected" <<<"$operational" || {
    echo "operational override missing: $expected" >&2
    exit 1
  }
done

if grep -Fq 'rushobs-clickhouse-init' <<<"$default_render"; then
  echo 'obsolete ClickHouse init ConfigMap is still rendered' >&2
  exit 1
fi

package_dir="$(mktemp -d)"
trap 'rm -rf "$package_dir"' EXIT
helm package "$chart_dir" --destination "$package_dir" >/dev/null
package="$(find "$package_dir" -maxdepth 1 -name 'rushobservability-*.tgz' -print -quit)"
helm show chart "$package" >/dev/null
helm template packaged "$package" >/dev/null
package_manifest="$package_dir/manifest.txt"
tar -tzf "$package" >"$package_manifest"
if grep -q '/tests/' "$package_manifest"; then
  echo '.helmignore did not exclude repository tests' >&2
  exit 1
fi
if ! grep -q '/values.schema.json$' "$package_manifest"; then
  echo 'packaged chart omitted values.schema.json' >&2
  exit 1
fi
if ! grep -q '/templates/helm-test-connectivity.yaml$' "$package_manifest"; then
  echo 'packaged chart omitted the native Helm test hook' >&2
  exit 1
fi

chart_version="$(awk '/^version:/ { print $2; exit }' "$chart_dir/Chart.yaml")"
app_version="$(awk '/^appVersion:/ { print $2; exit }' "$chart_dir/Chart.yaml")"
[[ "$chart_version" != '0.0.2' ]] || { echo 'chart version was not advanced' >&2; exit 1; }
[[ "$app_version" != '0.0.1' ]] || { echo 'appVersion is still stale' >&2; exit 1; }

echo 'network, ingress, helm-test, packaging, metadata, and override renders passed'
