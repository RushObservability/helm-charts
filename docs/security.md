# Security

[← Documentation](README.md)

## Ingest keys

Fresh tenants require authentication. Query and user keys cannot write
telemetry. Collectors need an ingest-only key scoped to their tenant, signals,
request rate, and optional source CIDRs.

For a new stack installation:

1. Install `rush-observability-stack`; add-ons default to off.
2. Enable a collector when needed.
3. Helm creates `<release>-ingest`, preserves it across upgrades, and Query API
   registers its HMAC for the default tenant.

```bash
helm upgrade rush rush/rush-observability-stack -n observability \
  --set collectors.mode=otel
```

Generated OpenTelemetry Collector and Vector configurations send the key as a
Bearer token. Set `global.rush.ingestApiKeySecret.autoGenerate=false` only when
authenticated add-ons are disabled or the tenant explicitly allows anonymous
ingest.

To use an externally managed Secret instead:

```bash
kubectl -n observability create secret generic rush-collector-ingest \
  --from-literal=api-key='rush_ing_...'

helm upgrade rush rush/rush-observability-stack -n observability \
  --set collectors.mode=otel \
  --set global.rush.ingestApiKeySecret.name=rush-collector-ingest
```

Query API registers the external key automatically if needed. It stores only
the HMAC; the plaintext stays in the Kubernetes Secret.

If the target tenant has **Require ingest key** turned off, explicitly allow
anonymous collector ingestion:

```bash
helm upgrade rush rush/rush-observability-stack -n observability \
  --set collectors.mode=otel \
  --set collectors.allowAnonymousIngest=true
```

Both the Helm flag and tenant policy must allow anonymous ingestion. Secure-key
ingestion remains the default.

### Upgrade notes

- Existing tenant rows are unchanged. Tenants without an explicit ingest policy
  inherit their query-auth setting, so previously open tenants stay open for
  ingestion.
- Existing API keys become `legacy` query-only keys. Create ingest keys before
  enabling or upgrading in-chart collectors.
- `queryApi.environment` defaults to `production`, and
  `queryApi.allowAnonymousDefault` defaults to `false`.
- For a default-tenant development override, set `environment: development`
  and `allowAnonymousDefault: true`. `/healthz` marks the deployment insecure.

Source restrictions use the direct peer address seen by Query API. If a proxy
terminates the collector connection, allowlist the proxy CIDR instead of an
untrusted forwarding header.

## Immutable production images

Every Rush image supports a `digest`. A valid `sha256:<64 lowercase hex
characters>` digest takes precedence over the tag.

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

`imageSecurity.requireDigests=true` rejects tag-only core Rush images. In the
stack, set `rush-observability.imageSecurity.requireDigests=true`; the same
policy also covers enabled SRE agent and collector images. Empty and `latest`
tags are always rejected.

Copy digests from each component's release workflow summary. Verify GitHub
provenance and SBOM attestations before deployment, and retain the named SPDX
artifact.

## Bootstrap secrets

The chart provisions:

- An initial admin password
- An API-key HMAC key
- An audit-log HMAC key
- A separate session-token HMAC key
- SSO and configuration encryption keys
- An internal SRE-agent token

Generated values live in the `<release>-bootstrap` Secret and are preserved
across upgrades.

### Option 1: Generate automatically

This is the default. Leave the values blank and retrieve the generated admin
password after installation:

```bash
kubectl -n <namespace> get secret <release>-bootstrap \
  -o jsonpath="{.data.initial-admin-password}" | base64 -d ; echo
```

Query API reads the password only while creating the initial account and never
prints credentials to its logs.

Explicit passwords must contain 12–1,024 UTF-8 bytes, include at least one
non-whitespace character, and not match a bundled common password. The default
24-character generated password meets this policy.

### Option 2: Set values

```bash
helm install rush rush/rush-observability \
  --set queryApi.adminPassword="$(openssl rand -base64 18)" \
  --set queryApi.apiKeyHmacSecret="$(openssl rand -hex 32)" \
  --set queryApi.auditHmacSecret="$(openssl rand -hex 32)" \
  --set queryApi.sessionHmacSecret="$(openssl rand -hex 32)" \
  --set global.sreAgent.internalAuthToken="$(openssl rand -hex 32)"
```

### Option 3: Bring your own Secret

Create the Secret before installing the chart:

```bash
kubectl create secret generic rush-bootstrap -n <namespace> \
  --from-literal=initial-admin-password="$(openssl rand -base64 18)" \
  --from-literal=api-key-hmac-secret="$(openssl rand -hex 32)" \
  --from-literal=audit-hmac-secret="$(openssl rand -hex 32)" \
  --from-literal=session-hmac-secret="$(openssl rand -hex 32)" \
  --from-literal=sso-transaction-secret="$(openssl rand -hex 32)" \
  --from-literal=config-encryption-key="$(openssl rand -hex 32)" \
  --from-literal=sre-agent-internal-token="$(openssl rand -hex 32)"

helm install rush rush/rush-observability -n <namespace> \
  --set queryApi.existingSecret=rush-bootstrap
```

Or create it declaratively:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rush-bootstrap
  namespace: <namespace>
type: Opaque
stringData:
  initial-admin-password: "choose-a-strong-password"
  audit-hmac-secret: "<random string, at least 32 bytes>"
  session-hmac-secret: "<random string, at least 32 bytes>"
  sso-transaction-secret: "<random string, at least 32 bytes>"
  config-encryption-key: "<random string, at least 32 bytes>"
  audit-hmac-previous-keys: ""
  sre-agent-internal-token: "<random string>"
```

HMAC secrets must be at least 32 bytes. Production startup rejects a weak audit
key.

To rotate the audit key, change `queryApi.audit.keyId` and retain old key
material in `audit-hmac-previous-keys` as a JSON object, such as
`{"primary":"old-secret"}`. The new segment stays linked to the previous tail,
and historical verification selects the key by ID.

## Audit durability

The audit outbox uses a retained 1 GiB PVC by default. It fsyncs every event
before ordered ClickHouse delivery. `/readyz` fails and audit queue metrics rise
while delivery is degraded.

Use `queryApi.audit.spool.persistence.existingClaim` for an operator-owned PVC.
Disable persistence only for local testing.

## Multi-replica SSO replay protection

For more than one Query API replica, enable ClickHouse Keeper so SAML assertion
IDs, OIDC transactions, and delegated SSO setup links are consumed atomically:

```yaml
queryApi:
  replicas: 2
  ssoReplayStore: auto

clickhouse:
  keeper:
    enabled: true
```

External ClickHouse must configure Keeper and `keeper_map_path_prefix`. Query
API fails startup instead of using a process-local replay cache with multiple
replicas.

## Browser sessions

Sessions default to a 30-minute idle timeout and a 24-hour absolute limit.
Authenticated activity rotates the HttpOnly bearer at most every five minutes.
Rotation renews only the idle deadline.

```yaml
queryApi:
  session:
    idleTimeoutSeconds: 1800
    absoluteTimeoutSeconds: 86400
    renewalIntervalSeconds: 300
```

The renewal interval must be at least 30 seconds and shorter than the idle
timeout. The absolute timeout must be at least the idle timeout and no longer
than 31 days. Invalid combinations stop Query API at startup.

Administrators can inspect and revoke sessions under **Settings → Users**.
Inventory reads, revocations, and bearer rotations are audited without storing
tokens or token hashes. ClickHouse stores keyed HMAC digests only. The first
upgrade to keyed storage revokes legacy raw or unkeyed session rows.
