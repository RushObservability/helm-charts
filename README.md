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

## Install

```bash
helm repo add rush https://RushObservability.github.io/helm-charts
helm repo update
helm install rush rush/rushobservability --namespace observability --create-namespace
```

Charts are published on tag by [chart-releaser](.github/workflows/release-charts.yml).

## Bootstrap secrets (admin password, audit HMAC key & SRE-agent token)

The chart needs three secrets: the **initial admin password** (`INITIAL_ADMIN_PASSWORD`, seeds the `admin` user on first boot), the **audit-log HMAC key** (`RUSH_AUDIT_HMAC_SECRET`, keys the tamper-evident audit hash-chain), and an internal **SRE-agent token** (`SRE_AGENT_INTERNAL_TOKEN`, which only query-api may use to call the agent). You have three options:

**1. Auto-generate (default).** Leave them blank and the chart generates a random admin password (24 chars) and HMAC key (64 chars) on first install, stores them in the `<release>-bootstrap` Secret, and **preserves them across upgrades** (and `helm uninstall`). Retrieve the generated admin password:

```bash
kubectl -n <namespace> get secret <release>-bootstrap \
  -o jsonpath="{.data.initial-admin-password}" | base64 -d ; echo
```

**2. Preset values.** Pin either/both:

```bash
helm install rush rush/rushobservability \
  --set queryApi.adminPassword="$(openssl rand -base64 18)" \
    --set queryApi.auditHmacSecret="$(openssl rand -hex 32)" \
    --set sreAgent.internalAuthToken="$(openssl rand -hex 32)"
```

**3. Bring your own Secret.** Create it **before** install, in the release namespace, with exactly these two keys, then point the chart at it with `queryApi.existingSecret` (the chart then creates no Secret of its own):

```bash
kubectl create secret generic rush-bootstrap -n <namespace> \
  --from-literal=initial-admin-password="$(openssl rand -base64 18)" \
  --from-literal=audit-hmac-secret="$(openssl rand -hex 32)" \
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
  sre-agent-internal-token: "<random string — e.g. `openssl rand -hex 32`>"
```

> **`audit-hmac-secret` must be ≥ 32 bytes.** It's used directly as the HMAC-SHA256 key (literal UTF-8 bytes — not hex-decoded), so the string's character count *is* the byte length; `openssl rand -hex 32` yields 64 bytes. A shorter/empty key makes the audit chain forgeable (query-api logs a warning). **Keep this value stable forever** — changing it makes all prior audit rows fail verification. `initial-admin-password` only seeds the admin user on first boot; changing it later does not rotate an existing admin.

## Read-only GitHub App access for the SRE agent

No webhooks are required. Create a GitHub App with only **Repository permissions
→ Contents: Read-only**, install it on selected repositories, and save its PEM
private key in a Kubernetes Secret:

```bash
kubectl -n <namespace> create secret generic rush-github-app \
  --from-file=private-key.pem=/path/to/github-app.private-key.pem
```

Enable the integration with values (the numeric installation ID is optional
here when each service link supplies its own):

```yaml
sreAgent:
  githubApp:
    enabled: true
    appId: "123456"
    defaultInstallationId: "654321"
    privateKeySecret:
      name: rush-github-app
      key: private-key.pem
```

The key is mounted read-only, source archives use a size-limited `emptyDir`, and
the agent requests short-lived installation tokens scoped to `contents: read`
and the single linked repository. Configure service-to-repository links in
Settings; repository scripts and Git hooks are never executed.

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

- [`rush-single.yaml`](examples/rush-single.yaml) — single-node, kick-the-tires
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
