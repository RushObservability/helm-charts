<div align="center">

# helm-charts

**Deploy [Rush](https://github.com/RushObservability) to Kubernetes.**

[![release](https://github.com/RushObservability/helm-charts/actions/workflows/release-charts.yml/badge.svg)](https://github.com/RushObservability/helm-charts/actions/workflows/release-charts.yml)
![license](https://img.shields.io/badge/license-BUSL--1.1-blue)

</div>

One chart, `rushobservability`, brings up the whole platform: ClickHouse, [query-api](https://github.com/RushObservability/query-api), the [frontend](https://github.com/RushObservability/frontend), and the [sre-agent](https://github.com/RushObservability/sre-agent) — plus, optionally, the collectors that feed them.

How data gets in is one switch, `collectors.mode`:

| mode | what the chart runs |
|---|---|
| `none` | nothing — point your own pipeline at query-api (default) |
| `otel` | an OpenTelemetry Collector (OTLP in) |
| `vector` | a Vector DaemonSet (tails pod logs) |
| `hybrid` | both |

## ClickHouse deployment modes

The default `clickhouse.mode: operator` uses the bundled Altinity ClickHouse
Operator. It is the recommended production mode because it manages
configuration, storage, scaling, upgrades, and cluster reconciliation.

For a single-node deployment without any ClickHouse operator, use the
operator-free profile:

```bash
helm install rush rush/rushobservability \
  --namespace observability --create-namespace \
  -f examples/rush-clickhouse-standalone.yaml
```

This creates one ClickHouse StatefulSet, Service, PVC, and configuration
Secret. It does not provide replicated ClickHouse or Keeper-based HA.

The chart also supports an existing ClickHouse deployment:

```yaml
clickhouse:
  enabled: false
  mode: external
  external:
    url: https://clickhouse.example:8443
    credentialsSecret: rush-clickhouse-credentials
    userKey: user
    passwordKey: password
    readCredentialsSecret: rush-clickhouse-read-credentials
    readUserKey: user
    readPasswordKey: password
```

Both external credential Secrets must already exist in the release namespace.
The first identity owns migrations and writes. The second must be a distinct
SELECT-only user with grants limited to the telemetry tables listed under
`clickhouse.clickhouse.users` in the chart values. External ClickHouse must also
set `custom_settings_prefixes` to `rush_`; query-api refuses to start if the
setting, strict row policies, read grants, or separate identity cannot be verified.

## Install

```bash
helm repo add rush https://RushObservability.github.io/helm-charts
helm repo update
helm install rush rush/rushobservability --namespace observability --create-namespace
```

Charts are published on tag by [chart-releaser](.github/workflows/release-charts.yml).

## Secure ingest keys

Fresh tenants require authentication. Query/user keys cannot write telemetry;
collectors need an ingest-only key scoped to their tenant, signals, request rate,
and optionally source CIDRs.

For a new installation, first install with the default `collectors.mode: none`,
sign in, and create an ingest key under **Settings → API Keys**. Store the key in
the release namespace, then enable the collector:

```bash
kubectl -n observability create secret generic rush-collector-ingest \
  --from-literal=api-key='rush_ing_...'

helm upgrade rush rush/rushobservability -n observability \
  --set collectors.mode=otel \
  --set collectors.ingestApiKeySecret.name=rush-collector-ingest
```

The generated OTel and Vector configurations send the key as a Bearer token.
By default, the chart refuses to render an enabled collector without
`collectors.ingestApiKeySecret.name`, preventing an accidentally anonymous or
nonfunctional pipeline.

If the target tenant explicitly has **Require ingest key** turned off, opt the
collector into anonymous ingestion instead:

```bash
helm upgrade rush rush/rushobservability -n observability \
  --set collectors.mode=otel \
  --set collectors.allowAnonymousIngest=true
```

The chart omits the Authorization header in this mode. The explicit Helm flag
and the tenant policy must both be configured; secure-key ingestion remains the
default.

### Upgrade migration

- Existing tenant rows are not silently changed. Tenants without an explicit
  ingest policy inherit their existing query-auth setting, so open tenants stay
  open for ingestion. Query and ingest authentication can then be changed
  independently in Settings.
- Existing API keys are classified as `legacy` and remain query-only. Create
  replacement ingest keys before enabling or upgrading in-chart collectors.
- `queryApi.environment` defaults to `production` and
  `queryApi.allowAnonymousDefault` defaults to `false`.
- For the global default-tenant development override, set `environment: development` and
  `allowAnonymousDefault: true`. `/healthz` marks the deployment insecure.

Source restrictions use the direct peer address observed by query-api. If an
ingress or service proxy terminates the collector connection, allowlist the
proxy's CIDR rather than an untrusted forwarding header.

## Scope query-api infrastructure access

Kubernetes, ArgoCD, and Flux pages use a separate `infrastructure:read` group
permission. Ordinary telemetry viewers do not receive it. The active Rush tenant
is already selected through group tenant bindings; `infrastructure.tenantNamespaces`
then maps that tenant to the only Kubernetes namespaces it may inspect.

```yaml
infrastructure:
  tenantNamespaces:
    acme: [acme-prod, acme-staging]
    "*": [shared-observability]

kubernetes:
  enabled: true
  namespaces: [acme-prod, acme-staging, shared-observability]
  clusterWide: false

argocd:
  enabled: true
  namespace: argocd

fluxcd:
  enabled: true
  namespace: flux-system
```

Add `argocd` or `flux-system` to only the tenants that should see those
integrations. The namespace map is deny-by-default: a missing tenant entry gets
`403`. The chart creates namespace Roles for each independently enabled
integration. ArgoCD and Flux roles contain only their own CRD API groups, and no
query-api role grants Secret access.

Cluster-wide Kubernetes browsing requires both `kubernetes.clusterWide: true`
and a `"*"` namespace grant for the tenant. This adds nodes/namespaces visibility
but still never grants or exposes Secrets. The query-api NetworkPolicy is enabled
by default; use `queryApi.networkPolicy.extraIngress` and `extraEgress` for ingress
controllers or external services that are not covered by the documented ports.

## Immutable production images

Every Rush image supports a separate `digest` value. A valid
`sha256:<64 lowercase hex characters>` digest takes precedence over `tag`, so
the running pod cannot change when a registry tag is moved. Copy the digest from
the corresponding release workflow summary:

```yaml
imageSecurity:
  requireDigests: true
queryApi:
  image:
    repository: ghcr.io/rushobservability/query-api
    digest: sha256:<release-digest>
frontend:
  image:
    repository: ghcr.io/rushobservability/web-ui
    digest: sha256:<release-digest>
```

`imageSecurity.requireDigests=true` rejects tag-only query-api and frontend
images, plus SRE-agent, anomaly-engine, and PostgreSQL collector images whenever
those workloads are enabled. The chart always rejects empty and `latest` tags,
and CI renders the full chart to prevent a dependency from reintroducing a
floating production image. Verify each image's GitHub provenance/SBOM
attestation before deployment and retain the SPDX artifact named in its release
workflow summary.

## Bootstrap secrets and audit durability

The chart provisions an **initial admin password**, an **audit-log HMAC key**, a
separate **session-token HMAC key**, SSO/config encryption keys, and an internal
**SRE-agent token**. The generated values are stored in the
`<release>-bootstrap` Secret and preserved across upgrades.

**1. Auto-generate (default).** Leave them blank and the chart generates strong
values on first install and preserves them across upgrades (and `helm
uninstall`). Retrieve the generated admin password:

```bash
kubectl -n <namespace> get secret <release>-bootstrap \
  -o jsonpath="{.data.initial-admin-password}" | base64 -d ; echo
```

The password is read from this Secret only while seeding the initial account;
query-api never prints generated or supplied credentials to its logs.
Explicit bootstrap passwords must satisfy the same policy as every later user
password: at least 12 Unicode characters, at least one non-whitespace
character, no more than 1,024 UTF-8 bytes, and not one of the bundled common
passwords. The default generated 24-character value satisfies this policy.

The audit outbox uses a retained 1 GiB PVC by default. Every audit event is
fsynced there before ordered ClickHouse delivery. `/readyz` fails and audit
queue metrics rise while delivery is degraded. Set
`queryApi.audit.spool.persistence.existingClaim` to use an operator-owned PVC;
disabling persistence is intended only for local testing.

For more than one query-api replica, enable ClickHouse Keeper so SAML
assertion IDs, OIDC transactions, and delegated SSO setup links are consumed
atomically across pods:

```yaml
queryApi:
  replicas: 2
  ssoReplayStore: auto
clickhouse:
  keeper:
    enabled: true
```

External ClickHouse deployments must configure Keeper and
`keeper_map_path_prefix`; the API fails startup rather than falling back to a
process-local replay cache in a multi-replica deployment.

Browser sessions default to a 30-minute idle timeout and a 24-hour hard limit.
Authenticated activity rotates the HttpOnly bearer every five minutes at most;
rotation renews only the idle deadline, never the hard limit. Configure the
policy in seconds:

```yaml
queryApi:
  session:
    idleTimeoutSeconds: 1800
    absoluteTimeoutSeconds: 86400
    renewalIntervalSeconds: 300
```

The renewal interval must be at least 30 seconds and shorter than the idle
timeout. The absolute timeout must be at least the idle timeout and cannot
exceed 31 days. Invalid combinations make query-api fail startup. Administrators
can inspect and revoke active sessions from **Settings → Users**; all admin
inventory reads, revocations, and bearer rotations are audited without recording
the token or token hash. ClickHouse stores only keyed HMAC digests. The first
upgrade to keyed storage revokes legacy raw/unkeyed session rows, so currently
signed-in users authenticate again once.

**2. Preset values.** Pin either/both:

```bash
helm install rush rush/rushobservability \
  --set queryApi.adminPassword="$(openssl rand -base64 18)" \
    --set queryApi.auditHmacSecret="$(openssl rand -hex 32)" \
    --set queryApi.sessionHmacSecret="$(openssl rand -hex 32)" \
    --set sreAgent.internalAuthToken="$(openssl rand -hex 32)"
```

**3. Bring your own Secret.** Create it **before** install in the release
namespace, then point the chart at it with `queryApi.existingSecret`:

```bash
kubectl create secret generic rush-bootstrap -n <namespace> \
  --from-literal=initial-admin-password="$(openssl rand -base64 18)" \
  --from-literal=audit-hmac-secret="$(openssl rand -hex 32)" \
  --from-literal=session-hmac-secret="$(openssl rand -hex 32)" \
  --from-literal=sso-transaction-secret="$(openssl rand -hex 32)" \
  --from-literal=config-encryption-key="$(openssl rand -hex 32)" \
  --from-literal=sre-agent-internal-token="$(openssl rand -hex 32)"

helm install rush rush/rushobservability -n <namespace> \
  --set queryApi.existingSecret=rush-bootstrap
```

Or declaratively (no manual base64):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rush-bootstrap
  namespace: <namespace>
type: Opaque
stringData:
  initial-admin-password: "choose-a-strong-password"
  audit-hmac-secret: "<random string, ≥ 32 bytes — e.g. `openssl rand -hex 32`>"
  session-hmac-secret: "<random string, ≥ 32 bytes — e.g. `openssl rand -hex 32`>"
  sso-transaction-secret: "<random string, ≥ 32 bytes>"
  config-encryption-key: "<random string, ≥ 32 bytes>"
  audit-hmac-previous-keys: ""
  sre-agent-internal-token: "<random string — e.g. `openssl rand -hex 32`>"
```

> **HMAC secrets must be at least 32 bytes.** Production startup fails for a
> weak audit key. To rotate it, set `queryApi.audit.keyId` to a new identifier
> and retain old key material in `audit-hmac-previous-keys` as a JSON object,
> for example `{"primary":"old-secret"}`. The new segment remains linked to
> the old tail and historical verification selects the correct key by ID.

## Read-only GitHub App access for the SRE agent

No webhooks are required. Create a GitHub App with only **Repository permissions
→ Contents: Read-only**, install it on selected repositories, and save its PEM
private key in a Kubernetes Secret:

```bash
kubectl -n <namespace> create secret generic rush-github-app \
  --from-file=private-key.pem=/path/to/github-app.private-key.pem
```

Enable the integration with an operator-owned tenant repository policy. Find a
repository's stable ID with `gh api repos/OWNER/REPO --jq .id`; the installation
ID appears at the end of its installed-app settings URL.

```yaml
sreAgent:
  githubApp:
    enabled: true
    appId: "123456"
    tenantRepositories:
      acme:
        - repository: acme/api
          installationId: 654321
          repositoryId: 123456789
    privateKeySecret:
      name: rush-github-app
      key: private-key.pem
```

The same deny-by-default policy is injected into query-api and the agent. Only
tenant admins can create links, and neither the browser nor API caller can
choose an installation or repository ID. The key is mounted read-only, source
archives use a size-limited `emptyDir`, and the agent requests short-lived
installation tokens scoped to `contents: read` and the stable repository ID.
Configure service-to-repository links in Settings; repository scripts and Git
hooks are never executed.

## Scope SRE-agent Kubernetes access

Kubernetes access is deny-by-default for the agent. Map Rush tenants to the
namespaces they may inspect, and the chart creates a dedicated service account
with read-only RoleBindings in only those namespaces:

```yaml
sreAgent:
  enabled: true
  kube:
    tenantNamespaces:
      acme: [acme-prod, acme-staging]
      "*": [shared-observability]
    allowClusterScopedForAdmins: false
```

By default the agent has no Secrets, pod-log, node, or namespace-enumeration
permissions. Set `allowClusterScopedForAdmins: true` only when node-level
diagnostics are required; this adds read-only nodes/namespaces RBAC, but the
agent still requires the `kube_cluster` scope, which query-api grants only to
administrators.

## Profiles

Worked example values in [`examples/`](examples) — start from the one closest to your setup:

- [`rush-single.yaml`](examples/rush-single.yaml) — single-node, operator-managed
- [`rush-clickhouse-standalone.yaml`](examples/rush-clickhouse-standalone.yaml) — one ClickHouse pod without the operator
- [`rush-clickhouse-external.yaml`](examples/rush-clickhouse-external.yaml) — connect to an existing ClickHouse
- [`rush-ha.yaml`](examples/rush-ha.yaml) — replicated query-api and frontend
- [`rush-retention.yaml`](examples/rush-retention.yaml) — per-signal retention
- [`rush-s3-tiering.yaml`](examples/rush-s3-tiering.yaml) — move cold data to object storage

```bash
helm install rush rush/rushobservability -f examples/rush-ha.yaml
```

## Configure

The knobs that matter most live under `queryApi`, `sreAgent`, `clickhouse`, `collectors`, and `retention` in [`values.yaml`](charts/rushobservability/values.yaml). The anomaly engine can run in-process or as its own Deployment; the SRE agent is opt-in (it needs an LLM key). Everything else has sane defaults.

## License

[Business Source License 1.1](LICENSE).
