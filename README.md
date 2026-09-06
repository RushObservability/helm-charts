<div align="center">

# Rush Helm charts

Install Rush Observability on Kubernetes.

[![release](https://github.com/RushObservability/helm-charts/actions/workflows/release-charts.yml/badge.svg)](https://github.com/RushObservability/helm-charts/actions/workflows/release-charts.yml)
![license](https://img.shields.io/badge/license-BUSL--1.1-blue)

</div>

## Try Rush

If you are unsure which chart to use, start with `rush-observability-stack`.
It installs Rush, a small single-node ClickHouse instance, Kubernetes log
collection, an OTLP endpoint, and metric discovery.

You need:

- Kubernetes 1.27 or newer
- Helm 3.8 or newer
- `kubectl` connected to the cluster
- A default StorageClass and about 4 GiB of available memory

Install the stack:

```bash
helm upgrade --install rush \
  oci://ghcr.io/rushobservability/helm-charts/rush-observability-stack \
  --namespace observability \
  --create-namespace
```

Wait for Rush to start:

```bash
kubectl -n observability rollout status statefulset/rush-clickhouse-standalone --timeout=5m
kubectl -n observability rollout status deployment/rush-query-api --timeout=5m
kubectl -n observability rollout status deployment/rush-frontend --timeout=5m
```

Open the UI:

```bash
kubectl -n observability port-forward svc/rush-frontend 8080:80
```

Visit [http://localhost:8080](http://localhost:8080). Sign in as `admin` with
the generated password:

```bash
kubectl -n observability get secret rush-bootstrap \
  -o jsonpath='{.data.initial-admin-password}' | base64 -d; echo
```

This setup is for a local cluster, evaluation, or a small development
environment. Start with the [getting started guide](docs/getting-started.md)
before installing Rush in production.

## What the first install collects

- Vector sends Kubernetes container logs to Rush.
- metrics-agent discovers Prometheus and VictoriaMetrics targets and adds
  `env=dev` to the metrics it sends.
- The OpenTelemetry Collector accepts OTLP on
  `rush-otel-collector.observability.svc:4317` and port `4318`.
- Helm generates the admin password and ingest key. You do not need to create
  either one for this install.

## Choose a chart

| Chart | Use it when |
|---|---|
| `rush-observability-stack` | You want Rush plus log, metric, trace, database, or SRE-agent collection. This is the usual choice. |
| `rush-observability` | You already run your own collectors and only need the Rush API, UI, and ClickHouse. |
| `metrics-agent` | You only need Kubernetes metric discovery and remote write. |

The charts are published as OCI packages under
`ghcr.io/rushobservability/helm-charts`. You do not need to add a Helm
repository.

## Common changes

| I want to… | Start here |
|---|---|
| Use a public hostname and TLS | [Production setup](docs/getting-started.md#move-to-production) |
| Use my existing ClickHouse cluster | [External ClickHouse](docs/clickhouse.md#external) |
| Change storage size or class | [Storage settings](docs/getting-started.md#storage) |
| Choose which telemetry collectors run | [Complete stack](docs/stack.md#enable-telemetry-collection) |
| Enable the SRE agent | [SRE agent](docs/stack.md#enable-the-sre-agent) |
| Configure SSO, Kubernetes, Argo CD, or Flux | [Access and integrations](docs/access-and-integrations.md) |
| Run multiple replicas | [Reliability and high availability](docs/reliability.md) |

Do not start by reading the full `values.yaml` files. They include every
advanced scheduling, security, and add-on setting. Use the guides above, then
look up an individual value when you need it.

## Documentation

- [Getting started](docs/getting-started.md)
- [All Helm guides](docs/README.md)
- [Core values reference](charts/rush-observability/values.yaml)
- [Stack values reference](charts/rush-observability-stack/values.yaml)
- [Example values](examples/)

## License

[Business Source License 1.1](LICENSE).
