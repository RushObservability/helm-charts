# Complete stack

[← Documentation](README.md)

`rush-observability-stack` is the umbrella chart. It installs the
`rush-observability` core chart and can also install cluster agents and
collectors with the same release.

Most installations should use this chart. If this is your first install,
follow [Getting started](getting-started.md) instead of building a values file
from this reference page.

## What is included

| Component | Default | Purpose |
|---|---:|---|
| Core Rush | On | Query API, frontend, anomaly processing, and ClickHouse |
| SRE agent | Off | AI-assisted investigation |
| metrics-agent | On | Discover Prometheus/VictoriaMetrics targets and remote-write metrics |
| OTel Collector | On | Receive OTLP traces and metrics |
| Vector | On | Collect Kubernetes container logs |
| PostgreSQL collector | Off | Paid PostgreSQL monitoring add-on |
| MySQL collector | Off | Paid MySQL query and database diagnostics add-on |

The SRE agent and licensed database add-ons are off initially because they need
an LLM provider, database credentials, or a license. The collection path and
shared ingest key work without extra configuration.

## Values layout

Core settings live under `rush`. Collectors and database add-ons remain at the
top level. `global` is reserved for settings shared across components, such as
scheduling, pod labels, image pull Secrets, and the generated ingest key.
Query API integrations live together under `rush.queryApi.integrations`.
Application behavior is grouped under `rush.queryApi.config`; Kubernetes
workload settings such as replicas, images, probes, resources, and scheduling
stay directly under `rush.queryApi`.

```yaml
rush:
  queryApi:
    replicas: 1
    config:
      runtime:
        baseUrl: https://rush.example.com
      authentication:
        allowAnonymousDefault: false
      retention:
        defaults:
          metricsDays: 30
          tracesDays: 30
          logsDays: 30
    integrations:
      kubernetes:
        enabled: false
  clickhouseStandalone:
    persistence:
      size: 100Gi

global:
  image:
    registry: "" # Set an internal registry mirror for Rush chart images.
  rush:
    # Optional: defaults to an automatically generated <release>-ingest Secret.
    ingestApiKeySecret: {}

collectors:
  mode: hybrid # none | otel | vector | hybrid

metricsAgent:
  enabled: true
  extraLabels:
    env: dev
```

The stack derives the in-cluster Query API URL and reuses the ingest Secret for
OTel Collector, Vector, and metrics-agent.

The Query API settings are split between application config and integrations:

| Group | Settings |
|---|---|
| `config.runtime` | Environment, public base URL, trusted proxies, and extra application environment variables |
| `config.authentication` | Anonymous access, SSO replay storage, login limits, and browser sessions |
| `config.promql` | PromQL staleness and lookback behavior |
| `config.secrets` | Generated secret presets or an externally managed bootstrap Secret |
| `config.audit` | Audit-chain key metadata and spool limits |
| `config.retention` | Default retention windows, signal-specific rules, and the retention enforcer |
| `config.ingest` | Protocol limits and durable ingest-buffer behavior |
| `integrations` | Kubernetes, Argo CD, Flux, CloudWatch, access recording, and the SRE agent |

For the core chart, remove only the leading `rush.` from these paths.

### Query API config migration

Move existing Query API application values as follows. Prefix both sides with
`rush.` when using the stack chart.

| Previous path | New path |
|---|---|
| `queryApi.environment`, `baseUrl`, `trustedProxyCidrs`, `env` | `queryApi.config.runtime.*` (`env` becomes `extraEnv`) |
| `queryApi.ssoReplayStore`, `loginRateLimit`, `session`, `allowAnonymousDefault` | `queryApi.config.authentication.*` |
| `queryApi.adminPassword`, HMAC/encryption keys, `existingSecret` | `queryApi.config.secrets.*` |
| `queryApi.audit.keyId`, `audit.previousKeysJson` | `queryApi.config.audit.*` |
| `queryApi.audit.spool.maxBytes` | `queryApi.config.audit.spoolMaxBytes` |
| `queryApi.ingestLimits` | `queryApi.config.ingest.limits` |
| `queryApi.buffer` | `queryApi.config.ingest.buffer` |
| `queryApi.buffer.drainWorker` | `queryApi.drainWorker` |
| `queryApi.audit.spool.persistence` | `queryApi.auditSpoolPersistence` |
| `queryApi.config.integrations` | `queryApi.integrations` |
| `rushConfig.retention` | `queryApi.config.retention` with camelCase field names |

The schemas reject the previous paths so an upgrade cannot appear successful
while ignoring an old override.

The stack values file shows the settings most installations change. Every
advanced core value remains available under `rush`; use the
[core values reference](../charts/rush-observability/values.yaml) when you need
pod-level, retention, or protocol tuning.

## Upgrade from stack 0.1

Version 0.2 makes the values tree consistent and changes the development
defaults. Before upgrading:

| Version 0.1 | Version 0.2 |
|---|---|
| `rush-observability.*` | `rush.*` |
| `global.sreAgent.*` | `rush.queryApi.integrations.sreAgent.*` |

The default stack now uses standalone ClickHouse, enables hybrid collection,
and enables metrics-agent. Existing production installations should set their
ClickHouse and collector choices explicitly in a values file. The schema
rejects the old keys so an upgrade cannot silently discard them.

## Migrating from the old combined chart

Install `rush-observability-stack` with the same release name, then move values:

| Old core value | Stack value |
|---|---|
| Core settings such as `queryApi` and `clickhouse` | `rush.queryApi`, `rush.clickhouse` |
| `sreAgent` | `rush.queryApi.integrations.sreAgent` |
| `infrastructure`, `argocd`, `fluxcd`, `kubernetes`, `cloudwatch` | `rush.queryApi.integrations.*` |
| `queryApi.kubernetesAccess` | `rush.queryApi.integrations.kubernetesAccess` |
| `promql` | `rush.queryApi.config.promql` |
| `collectors` | `collectors` |
| `collectors.ingestApiKeySecret` | `global.rush.ingestApiKeySecret` |
| `enterprise.license.integrations.postgresCollector` | `postgresCollector` |
| `enterprise.license` | `rush.enterprise.license` |

The core chart now rejects the removed top-level collector and SRE-agent keys
so upgrades do not silently ignore old values.

## Enable telemetry collection

Enable the components you need. Helm generates `<release>-ingest` on first
install, preserves it across upgrades, and Query API registers it as an
ingest-only key for logs, traces, metrics, and RUM:

```bash
helm upgrade rush \
  oci://ghcr.io/rushobservability/helm-charts/rush-observability-stack \
  -n observability \
  --set collectors.mode=hybrid \
  --set metricsAgent.enabled=true \
  --set-string metricsAgent.extraLabels.env=dev
```

To use an externally managed Secret instead:

```bash
kubectl -n observability create secret generic rush-ingest \
  --from-literal=api-key='rush_ing_...'

helm upgrade rush \
  oci://ghcr.io/rushobservability/helm-charts/rush-observability-stack \
  -n observability \
  --set collectors.mode=hybrid \
  --set metricsAgent.enabled=true \
  --set global.rush.ingestApiKeySecret.name=rush-ingest
```

Query API also registers an external key if it is not already present. An
explicit `global.rush.ingestApiKeySecret.value` remains available, but values
are stored in Helm release history and may remain in shell history.

Use `otel` for a central OTLP gateway, `vector` for node-local logs, or
`hybrid` for OTel traces/metrics plus Vector logs.

## Enable the SRE agent

```bash
helm upgrade rush \
  oci://ghcr.io/rushobservability/helm-charts/rush-observability-stack \
  -n observability \
  --set rush.queryApi.integrations.sreAgent.enabled=true \
  --set rush.queryApi.networkPolicy.allowExternalHttpsEgress=true
```

Then open **Settings → AI Agent** in Rush, connect an LLM provider, and add a
model. Query API stores the credential encrypted and makes provider requests;
the SRE agent receives neither the credential nor direct provider access.

See [access and integrations](access-and-integrations.md) before granting the
agent Kubernetes or GitHub access.

## Enable PostgreSQL monitoring

The PostgreSQL collector requires a license with the PostgreSQL entitlement,
the Rush license Secret, and a Secret containing `dsn` and `api-key`. It also
requires an explicit NetworkPolicy egress rule for the database.

See the defaults under [`postgresCollector`](../charts/rush-observability-stack/values.yaml)
for the complete configuration.

## Enable MySQL monitoring

Create a Secret with a read-only MySQL DSN and Rush ingest key, then enable the collector. When NetworkPolicy is on, add a narrow TCP 3306 egress rule for the database.

```bash
kubectl -n observability create secret generic rush-mysql-collector \
  --from-literal=dsn='mysql://rush_monitor:…@mysql.example:3306/app' \
  --from-literal=api-key='rush_ing_…'

helm upgrade rush \
  oci://ghcr.io/rushobservability/helm-charts/rush-observability-stack \
  -n observability \
  --set mysqlCollector.enabled=true \
  --set-json 'mysqlCollector.networkPolicy.extraEgress=[{"to":[{"ipBlock":{"cidr":"10.40.0.8/32"}}],"ports":[{"protocol":"TCP","port":3306}]}]'
```

The license must include the `mysql` entitlement. Error message text remains off unless `mysqlCollector.env.COLLECTOR_INCLUDE_ERROR_TEXT=true` is set explicitly.
