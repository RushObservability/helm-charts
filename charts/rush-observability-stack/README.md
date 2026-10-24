# rush-observability-stack

![Version: 0.4.6](https://img.shields.io/badge/Version-0.4.6-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.1.7](https://img.shields.io/badge/AppVersion-0.1.7-informational?style=flat-square)

**Start here.** This is the chart most people want: it installs Rush plus a
single-node ClickHouse, Kubernetes log collection, an OTLP endpoint, and metric
discovery. It installs [rush-observability](../rush-observability) for you.

Rush Observability with optional cluster agents and telemetry collectors

**Homepage:** <https://rushobservability.com>

## Quick start

No values are required for an evaluation install:

```bash
helm upgrade --install rush \
  oci://ghcr.io/rushobservability/helm-charts/rush-observability-stack \
  --namespace observability --create-namespace
```

Then get the generated admin password and open the UI:

```bash
kubectl -n observability get secret rush-bootstrap \
  -o jsonpath='{.data.initial-admin-password}' | base64 -d; echo
kubectl -n observability port-forward svc/rush-frontend 8080:80
```

Read [Getting started](../../docs/getting-started.md) before installing in
production.

## Guides

| Goal | Guide |
|---|---|
| First install and login | [Getting started](../../docs/getting-started.md) |
| Pick core vs stack | [Choose a chart](../../docs/stack.md) |
| Operator, standalone, or external ClickHouse | [ClickHouse](../../docs/clickhouse.md) |
| Replicas and safe rollouts | [Reliability](../../docs/reliability.md) |
| NetworkPolicies, ingress, TLS | [Networking](../../docs/networking.md) |
| Ingest keys, secrets, image digests | [Security](../../docs/security.md) |

Ready-made values files live in [examples/](../../examples/).

## Requirements

Kubernetes: `>=1.27.0-0`

| Repository | Name | Version |
|------------|------|---------|
| file://../metrics-agent | metricsAgent(metrics-agent) | 0.1.6 |
| file://../rush-observability | rush(rush-observability) | 0.5.6 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| collectors | object | see values.yaml | Telemetry collection. Hybrid means OTel receives traces and metrics while Vector tails Kubernetes logs. Set mode to none to use external collectors. |
| collectors.otel.configOverride | string | `""` | Full collector config to use instead of the generated one. Include the health_check extension on 0.0.0.0:13133; the pod probes depend on it. |
| global | object | `{"extraEnvFrom":[],"extraVolumeMounts":[],"extraVolumes":[],"image":{"registry":""},"imagePullSecrets":[],"podAnnotations":{},"podLabels":{},"priorityClassName":"","runtimeClassName":"","rush":{"ingestApiKeySecret":{"autoGenerate":true,"key":"api-key","name":"","value":""},"queryApi":{"port":8080,"serviceName":""},"queryApiIngressComponents":["otel-collector","vector","metrics-agent"],"stack":{"enabled":true}},"scheduling":{"affinity":{},"nodeSelector":{},"tolerations":[],"topologySpreadConstraints":[]},"serviceAccount":{"annotations":{}}}` | Shared Kubernetes defaults inherited by application and collector workloads. |
| global.image.registry | string | `""` | Optional registry mirror for images rendered by the Rush charts. Example: mirror.example.com or mirror.example.com/dockerhub |
| global.rush | object | `{"ingestApiKeySecret":{"autoGenerate":true,"key":"api-key","name":"","value":""},"queryApi":{"port":8080,"serviceName":""},"queryApiIngressComponents":["otel-collector","vector","metrics-agent"],"stack":{"enabled":true}}` | Stack plumbing. Leave stack, ingress component names, and service details unchanged. ingestApiKeySecret may point to an externally managed Secret. |
| global.rush.ingestApiKeySecret | object | `{"autoGenerate":true,"key":"api-key","name":"","value":""}` | Rush ingest-only API key shared by Query API, OTel Collector, Vector, and metrics-agent. By default Helm generates and registers it automatically. |
| global.rush.ingestApiKeySecret.autoGenerate | bool | `true` | Generate <release>-ingest on first install and preserve it on upgrades. Set false only for anonymous ingest or when no authenticated add-on is used. |
| global.rush.ingestApiKeySecret.name | string | `""` | Set a name to use an externally managed Secret instead. |
| global.rush.ingestApiKeySecret.value | string | `""` | Optional explicit key. This creates the chart-managed Secret and takes precedence over automatic generation. It is stored in release history. |
| global.rush.queryApi.serviceName | string | `""` | Blank resolves to <release>-query-api. |
| metricsAgent | object | `{"enabled":true,"extraLabels":{"env":"dev"},"nameOverride":"metrics-agent","rushRemoteWrite":{"allowAnonymous":false,"enabled":true,"url":""}}` | Prometheus-compatible target discovery and remote write. |
| rush | object | see values.yaml | Start here. `rush` contains the API, UI, ClickHouse, ingress, and integration settings. The stack defaults are sized for a development or evaluation cluster: standalone ClickHouse, a 20 GiB volume, and localhost access. Production examples are documented in docs/getting-started.md.  Most installations only change:   rush.queryApi, rush.clickhouse,   global.scheduling, collectors, and metricsAgent.extraLabels. |
| rush.clickhouse.clickhouse | object | `{"markCacheSize":536870912,"resources":{"limits":{"memory":"4Gi"},"requests":{"memory":"2Gi"}},"textIndexHeaderCacheSize":268435456,"textIndexPostingsCacheSize":536870912,"textIndexTokensCacheSize":134217728,"uncompressedCacheSize":67108864}` | ClickHouse server sizing, used in standalone and operator mode. Raise the memory limit and the caches together; the caches below total about 1.4 GiB, leaving the rest of the 4Gi limit for queries and merges. |
| rush.clickhouse.enabled | bool | `false` | Helm dependency gate. Keep false for standalone/external and set true with mode=operator. |
| rush.queryApi.integrations.sreAgent.enabled | bool | `false` | Optional investigation service. Provider credentials remain in Query API; the agent receives only short-lived requests and its internal token. |

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Mike Zupan | <mike@zcentric.com> | <https://github.com/mzupan> |

## Source Code

* <https://github.com/RushObservability/helm-charts>
