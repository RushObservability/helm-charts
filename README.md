<div align="center">

# Rush Helm charts

**Deploy [Rush](https://github.com/RushObservability) to Kubernetes.**

[![release](https://github.com/RushObservability/helm-charts/actions/workflows/release-charts.yml/badge.svg)](https://github.com/RushObservability/helm-charts/actions/workflows/release-charts.yml)
![license](https://img.shields.io/badge/license-BUSL--1.1-blue)

</div>

## Choose a chart

| Chart | Installs | Use it when |
|---|---|---|
| `rushobservability` | Query API, frontend, anomaly engine, and ClickHouse | You already collect telemetry or want only the Rush platform. |
| `rush-observability-stack` | Core Rush plus optional SRE agent, metrics-agent, Vector, OTel Collector, and PostgreSQL collector | You want one chart to manage the complete observability stack. |
| `metrics-agent` | The standalone Rush metrics agent | You only need Kubernetes metric discovery and remote write. |

## Quick install

Install the complete stack with add-ons disabled until you create an ingest key:

```bash
helm repo add rush https://RushObservability.github.io/helm-charts
helm repo update
helm install rush rush/rush-observability-stack \
  --namespace observability \
  --create-namespace
```

Install only core Rush:

```bash
helm install rush rush/rushobservability \
  --namespace observability \
  --create-namespace
```

## Next steps

- [Configure the complete stack](docs/stack.md)
- [Choose a ClickHouse mode](docs/clickhouse.md)
- [Secure ingest and secrets](docs/security.md)
- [Run Rush reliably](docs/reliability.md)
- [Browse all documentation](docs/README.md)

Core examples are in [`examples/`](examples/). For every setting, see the
[core values](charts/rushobservability/values.yaml), [stack
values](charts/rush-observability-stack/values.yaml), and [metrics-agent
values](charts/metrics-agent/values.yaml).

## License

[Business Source License 1.1](LICENSE).
