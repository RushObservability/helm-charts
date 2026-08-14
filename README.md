<div align="center">

# Rush Helm charts

**Deploy [Rush](https://github.com/RushObservability) to Kubernetes.**

[![release](https://github.com/RushObservability/helm-charts/actions/workflows/release-charts.yml/badge.svg)](https://github.com/RushObservability/helm-charts/actions/workflows/release-charts.yml)
![license](https://img.shields.io/badge/license-BUSL--1.1-blue)

</div>

The `rushobservability` chart installs the Rush platform: ClickHouse, Query API,
and frontend, with optional SRE agent and telemetry collectors.

## Quick install

```bash
helm repo add rush https://RushObservability.github.io/helm-charts
helm repo update
helm install rush rush/rushobservability \
  --namespace observability \
  --create-namespace
```

Check the release:

```bash
helm test rush --namespace observability --logs
```

## Choose a collector

Set `collectors.mode` based on how telemetry reaches Rush:

| Mode | Chart-managed collector |
|---|---|
| `none` | None. Send telemetry from your existing pipeline. This is the default. |
| `otel` | OpenTelemetry Collector with OTLP ingestion. |
| `vector` | Vector DaemonSet that tails Kubernetes pod logs. |
| `hybrid` | OpenTelemetry Collector and Vector. |

Before enabling a collector, create an ingest key under **Settings → API Keys**.
See [ingest key setup](docs/security.md#ingest-keys).

## Start from an example

| Deployment | Values file |
|---|---|
| Single-node, operator-managed ClickHouse | [`rush-single.yaml`](examples/rush-single.yaml) |
| Standalone ClickHouse without an operator | [`rush-clickhouse-standalone.yaml`](examples/rush-clickhouse-standalone.yaml) |
| Existing external ClickHouse | [`rush-clickhouse-external.yaml`](examples/rush-clickhouse-external.yaml) |
| High availability | [`rush-ha.yaml`](examples/rush-ha.yaml) |
| Per-signal retention | [`rush-retention.yaml`](examples/rush-retention.yaml) |
| S3 cold-data tiering | [`rush-s3-tiering.yaml`](examples/rush-s3-tiering.yaml) |
| Dedicated application and ClickHouse nodes | [`rush-node-groups.yaml`](examples/rush-node-groups.yaml) |

Install with an example:

```bash
helm install rush rush/rushobservability \
  --namespace observability \
  --create-namespace \
  -f examples/rush-ha.yaml
```

## Documentation

- [All Helm chart docs](docs/README.md)
- [ClickHouse deployment modes](docs/clickhouse.md)
- [Reliability and high availability](docs/reliability.md)
- [Networking and ingress](docs/networking.md)
- [Security, ingest keys, and secrets](docs/security.md)
- [Scheduling and dedicated node groups](docs/scheduling.md)
- [Access and integrations](docs/access-and-integrations.md)
- [Operations and release testing](docs/operations.md)

For every setting, see the [default values](charts/rushobservability/values.yaml)
and [values schema](charts/rushobservability/values.schema.json).

## License

[Business Source License 1.1](LICENSE).
