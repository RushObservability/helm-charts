# Complete stack

[← Documentation](README.md)

`rush-observability-stack` is the umbrella chart. It installs the
`rushobservability` core chart and can also install cluster agents and
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

Add-ons are off initially because they need an ingest key, LLM key, database
credentials, or a paid license.

## Values layout

Core settings live under `rushobservability`. Stack add-ons remain at the top
level. Shared connection settings live under `global`.

```yaml
rushobservability:
  queryApi:
    replicas: 2
  clickhouse:
    keeper:
      enabled: true

global:
  rush:
    ingestApiKeySecret:
      name: rush-ingest
      key: api-key

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
| Core settings such as `queryApi` and `clickhouse` | `rushobservability.queryApi`, `rushobservability.clickhouse` |
| `sreAgent` | `global.sreAgent` |
| `collectors` | `collectors` |
| `collectors.ingestApiKeySecret` | `global.rush.ingestApiKeySecret` |
| `enterprise.license.integrations.postgresCollector` | `postgresCollector` |
| `enterprise.license` | `rushobservability.enterprise.license` |

The core chart now rejects the removed top-level collector and SRE-agent keys
so upgrades do not silently ignore old values.

## Enable telemetry collection

First install the stack, sign in, and create an ingest-only API key under
**Settings → API Keys**. Store it in the release namespace:

```bash
kubectl -n observability create secret generic rush-ingest \
  --from-literal=api-key='rush_ing_...'
```

Then enable the components you need:

```bash
helm upgrade rush rush/rush-observability-stack -n observability \
  --set global.rush.ingestApiKeySecret.name=rush-ingest \
  --set collectors.mode=hybrid \
  --set metricsAgent.enabled=true \
  --set-string metricsAgent.extraLabels.env=dev
```

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
