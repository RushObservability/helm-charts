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
