# Complete stack

[← Documentation](README.md)

`rush-observability-stack` is the umbrella chart. It installs the
`rush-observability` core chart and can also install cluster agents and
collectors with the same release.

## What is included

| Component | Default | Purpose |
|---|---:|---|
| Core Rush | On | Query API, frontend, anomaly processing, and ClickHouse |
| SRE agent | Off | AI-assisted investigation |
| metrics-agent | Off | Discover Prometheus/VictoriaMetrics targets and remote-write metrics |
| OTel Collector | Off | Receive OTLP traces, metrics, and logs |
| Vector | Off | Collect Kubernetes container logs; optionally receive OTLP |
| PostgreSQL collector | Off | Paid PostgreSQL monitoring add-on |

Add-ons are off initially because some need an LLM key, database credentials,
or a paid license. The shared ingest key is generated automatically.

## Values layout

Core settings live under `rush-observability`. Stack add-ons remain at the top
level. Shared connection settings live under `global`.

```yaml
rush-observability:
  queryApi:
    replicas: 2
  clickhouse:
    keeper:
      enabled: true

global:
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

## Migrating from the old combined chart

Install `rush-observability-stack` with the same release name, then move values:

| Old core value | Stack value |
|---|---|
| Core settings such as `queryApi` and `clickhouse` | `rush-observability.queryApi`, `rush-observability.clickhouse` |
| `sreAgent` | `global.sreAgent` |
| `collectors` | `collectors` |
| `collectors.ingestApiKeySecret` | `global.rush.ingestApiKeySecret` |
| `enterprise.license.integrations.postgresCollector` | `postgresCollector` |
| `enterprise.license` | `rush-observability.enterprise.license` |

The core chart now rejects the removed top-level collector and SRE-agent keys
so upgrades do not silently ignore old values.

## Enable telemetry collection

Enable the components you need. Helm generates `<release>-ingest` on first
install, preserves it across upgrades, and Query API registers it as an
ingest-only key for logs, traces, metrics, and RUM:

```bash
helm upgrade rush rush/rush-observability-stack -n observability \
  --set collectors.mode=hybrid \
  --set metricsAgent.enabled=true \
  --set-string metricsAgent.extraLabels.env=dev
```

To use an externally managed Secret instead:

```bash
kubectl -n observability create secret generic rush-ingest \
  --from-literal=api-key='rush_ing_...'

helm upgrade rush rush/rush-observability-stack -n observability \
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
kubectl -n observability create secret generic openai \
  --from-literal=api-key='<key>'

helm upgrade rush rush/rush-observability-stack -n observability \
  --set global.sreAgent.enabled=true \
  --set global.sreAgent.llmApiKeySecret.name=openai \
  --set global.sreAgent.networkPolicy.allowExternalHttpsEgress=true
```

See [access and integrations](access-and-integrations.md) before granting the
agent Kubernetes or GitHub access.

## Enable PostgreSQL monitoring

The PostgreSQL collector requires a license with the PostgreSQL entitlement,
the Rush license Secret, and a Secret containing `dsn` and `api-key`. It also
requires an explicit NetworkPolicy egress rule for the database.

See the defaults under [`postgresCollector`](../charts/rush-observability-stack/values.yaml)
for the complete configuration.
