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
queryApi:
  networkPolicy:
    allowExternalClickHouseEgress: true # or use a CIDR-specific extraEgress rule
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

## Scheduling and dedicated node groups

`global.scheduling` sets shared scheduling defaults for Rush-owned workloads:
query-api, frontend, SRE agent, anomaly engine, OTel, Vector, and licensed
collectors. ClickHouse does not inherit these defaults, so storage pods can use
a separate node group:

```yaml
global:
  scheduling:
    nodeSelector:
      nodegroup: rush-apps
    tolerations:
      - key: rush-apps
        operator: Equal
        value: "true"
        effect: NoSchedule

clickhouse:
  clickhouse:
    nodeSelector:
      nodegroup: clickhouse
    tolerations:
      - key: clickhouse
        operator: Equal
        value: "true"
        effect: NoSchedule
  keeper:
    nodeSelector:
      nodegroup: clickhouse
    tolerations:
      - key: clickhouse
        operator: Equal
        value: "true"
        effect: NoSchedule
  # The operator and CRD hook are control-plane workloads, not ClickHouse data
  # pods. Schedule them explicitly when every node group is tainted.
  operator:
    nodeSelector:
      nodegroup: rush-apps
    tolerations:
      - key: rush-apps
        operator: Equal
        value: "true"
        effect: NoSchedule
    crdHook:
      nodeSelector:
        nodegroup: rush-apps
      tolerations:
        - key: rush-apps
          operator: Equal
          value: "true"
          effect: NoSchedule
```

Every Rush workload has a `scheduling` override. `nodeSelector` and `affinity`
maps deep-merge over the global maps; `tolerations` and
`topologySpreadConstraints` replace the global lists when supplied locally.
For example, this keeps global affinity and tolerations but moves query-api to
another node group:

```yaml
queryApi:
  scheduling:
    nodeSelector:
      nodegroup: rush-api
```

Set `inheritGlobalScheduling: false` on a workload to ignore all global
scheduling defaults. This is especially useful for `collectors.vector`, whose
DaemonSet otherwise runs only on nodes matching the global selector. Standalone
ClickHouse uses `clickhouseStandalone.nodeSelector`, `tolerations`, `affinity`,
and `topologySpreadConstraints`. The bundled Altinity operator can be scheduled
separately with `clickhouse.operator.nodeSelector`, `tolerations`, `affinity`,
and `topologySpreadConstraints`; its install hook uses the corresponding
`clickhouse.operator.crdHook` values.

## High-availability ingest buffering

A pod-local disk queue is intentionally the default for one query-api replica.
It is not safe for HA because another pod cannot replay telemetry stranded on a
failed node. When `queryApi.replicas` is greater than one, the chart requires an
S3-compatible shared buffer and deploys exactly one dedicated drain worker:

```bash
kubectl -n observability create secret generic rush-ingest-buffer \
  --from-literal=access-key='<access-key>' \
  --from-literal=secret-key='<secret-key>'
```

```yaml
queryApi:
  replicas: 3
  buffer:
    backend: object_store
    maxBytes: 2147483648
    objectStore:
      endpoint: "" # blank for AWS; set for MinIO, Ceph, or RustFS
      bucket: rush-ingest-buffer
      prefix: ingest/
      region: us-east-1
      credentialsSecret:
        name: rush-ingest-buffer
        accessKeyKey: access-key
        secretKeyKey: secret-key
    drainWorker:
      enabled: true
  networkPolicy:
    allowExternalHttpsEgress: true # or use a bucket-specific extraEgress rule

clickhouse:
  keeper:
    enabled: true
```

API pods enqueue but do not replay objects when the worker is enabled. The
worker is fixed at one replica and uses a `Recreate` rollout so upgrades cannot
briefly run two drainers. Object-store credentials are read only from the named
Secret. See [`examples/rush-ha.yaml`](examples/rush-ha.yaml) for a complete HA
profile. The chart rejects multi-replica API values that omit any of these
requirements.

## Availability, rollouts, and health probes

First-party Deployments expose a `rollout` block, and each workload exposes an
opt-in `podDisruptionBudget`. Stateless serving paths use zero-unavailable
rolling updates by default. Singleton consumers such as the anomaly engine,
Postgres collector, and ingest drain worker default to `Recreate` to avoid
duplicate work.

```yaml
queryApi:
  rollout:
    strategy: RollingUpdate
    maxUnavailable: 0
    maxSurge: 1
    minReadySeconds: 10
    progressDeadlineSeconds: 600
    revisionHistoryLimit: 10
  podDisruptionBudget:
    enabled: true
    type: minAvailable # or maxUnavailable
    value: 2           # integer or percentage
```

Do not enable `minAvailable: 1` on a singleton unless blocking voluntary node
drains is intentional. OTel and Vector DaemonSets also have configurable update
strategies; standalone ClickHouse exposes its StatefulSet update strategy and
PDB under `clickhouseStandalone`.

Query-api, frontend, SRE agent, OTel, and standalone ClickHouse expose startup,
readiness, and liveness settings. A startup probe protects slow initialization
from premature liveness restarts. Each probe can be tuned or disabled:

```yaml
queryApi:
  probes:
    startup:
      enabled: true
      path: /healthz
      initialDelaySeconds: 0
      periodSeconds: 5
      timeoutSeconds: 2
      failureThreshold: 60
      successThreshold: 1
```

The chart includes `values.schema.json`. `helm lint`, `helm template`, install,
and upgrade validate core enums, numeric ranges, image digests, rollout/PDB/probe
shapes, and the HA buffer contract before resources are submitted to Kubernetes.

## Network isolation

NetworkPolicies are enabled for query-api, frontend, SRE agent, anomaly engine,
OTel, Vector, the PostgreSQL collector, the drain worker, and standalone
ClickHouse. Default rules permit only required component-to-component traffic,
DNS, and same-namespace collector ingestion. Query-api no longer accepts traffic
from every pod in the namespace and receives no broad Internet egress by default.

Enable broad destinations only when the feature needs them, or prefer a
CIDR-specific `extraEgress` rule:

```yaml
queryApi:
  networkPolicy:
    allowExternalHttpsEgress: true     # OIDC/SAML, webhooks, S3 buffer
    allowExternalClickHouseEgress: false
    allowSmtpEgress: false
    extraIngress: []                   # ingress controller or external collector
    extraEgress: []

sreAgent:
  enabled: true
  networkPolicy:
    allowExternalHttpsEgress: true     # OpenAI/GitHub/Kubernetes API
```

The PostgreSQL collector requires an explicit `networkPolicy.extraEgress` rule
for the monitored database. External ClickHouse requires either
`allowExternalClickHouseEgress` or an explicit rule. The chart fails rendering
instead of deploying a workload that cannot reach a required external service.

## Ingress and TLS

The optional Ingress exposes the frontend, which already proxies `/api`,
`/auth`, `/prom`, and `/metrics`. A separate direct API host is also available
for integrations that should not traverse the frontend proxy:

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
  trustedProxyCidrs: [10.42.0.0/16]
  frontend:
    host: rush.example.com
    tls:
      enabled: true
      secretName: rush-tls
  api:
    enabled: true
    host: api.rush.example.com
    tls:
      enabled: true
      secretName: rush-api-tls
```

When `queryApi.baseUrl` is empty, the chart derives it from the frontend TLS
host. `ingress.trustedProxyCidrs` is merged into query-api's trusted proxy list.
Add an `extraIngress` rule matching your ingress controller's namespace/pod
labels when it does not run in the release namespace.

## Operational overrides

Shared pod defaults live under `global`; every Rush-owned workload can override
them. Annotation and label maps merge. Non-empty component lists/scalars replace
the corresponding global value.

```yaml
global:
  podAnnotations: { cluster-autoscaler.kubernetes.io/safe-to-evict: "true" }
  podLabels: { platform.example.com/tier: observability }
  imagePullSecrets: [{ name: registry-credentials }]
  priorityClassName: platform-critical
  runtimeClassName: gvisor
  extraEnvFrom: []
  extraVolumes: []
  extraVolumeMounts: []
  serviceAccount:
    annotations: { eks.amazonaws.com/role-arn: arn:aws:iam::123:role/rush }

queryApi:
  serviceAccount:
    create: true
    name: ""
    annotations: {}
```

Supported workload fields are `podAnnotations`, `podLabels`,
`imagePullSecrets`, `priorityClassName`, `runtimeClassName`, `extraEnvFrom`,
`extraVolumes`, `extraVolumeMounts`, and `serviceAccount.create/name/annotations`.
Reserved selector labels cannot be overridden.

## Installed-release and package tests

Run the native connectivity checks after installation:

```bash
helm test rush -n observability --logs
```

The test verifies query-api health/readiness, frontend availability, frontend
proxying, and optionally authenticated ClickHouse connectivity. Configure it
under `helmTests`, or set `helmTests.enabled: false` to omit the hook.

Repository render tests remain in Git but `.helmignore` excludes them from the
published archive. CI requires a chart-version bump for chart changes, runs the
render suite, validates the packaged archive, renders from the archive, and
refuses packages that accidentally contain `tests/`.

## Install

```bash
helm repo add rush https://RushObservability.github.io/helm-charts
helm repo update
helm install rush rush/rushobservability --namespace observability --create-namespace
```

Charts are published to GHCR when versioned chart changes reach `main` by the
[release workflow](.github/workflows/release-charts.yml).

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
but still never grants or exposes Secrets. Kubernetes API access also needs
`queryApi.networkPolicy.allowExternalHttpsEgress: true` or a narrower explicit
egress rule because broad external egress is disabled by default.

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
  enabled: true
  networkPolicy:
    allowExternalHttpsEgress: true
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
- [`rush-node-groups.yaml`](examples/rush-node-groups.yaml) — Rush workloads and ClickHouse on separate node groups

```bash
helm install rush rush/rushobservability -f examples/rush-ha.yaml
```

## Configure

The knobs that matter most live under `queryApi`, `sreAgent`, `clickhouse`, `collectors`, and `retention` in [`values.yaml`](charts/rushobservability/values.yaml). The anomaly engine can run in-process or as its own Deployment; the SRE agent is opt-in (it needs an LLM key). Everything else has sane defaults.

## License

[Business Source License 1.1](LICENSE).
