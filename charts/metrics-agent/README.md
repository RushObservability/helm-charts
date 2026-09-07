# metrics-agent

![Version: 0.1.4](https://img.shields.io/badge/Version-0.1.4-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.1.0](https://img.shields.io/badge/AppVersion-0.1.0-informational?style=flat-square)

Cluster-wide metric collection from Prometheus and VictoriaMetrics CRDs.

> Normally installed for you by
> [rush-observability-stack](../rush-observability-stack). Install it directly
> only when you want metric discovery without the rest of Rush.

Cluster-wide Prometheus and VictoriaMetrics CRD metric collection with deterministic VM precedence

**Homepage:** <https://rushobservability.com>

## Install

```bash
helm upgrade --install metrics-agent \
  oci://ghcr.io/rushobservability/helm-charts/metrics-agent \
  --namespace observability --create-namespace \
  --set global.rush.queryApi.serviceName=rush-query-api
```

The agent reads `ServiceMonitor`, `PodMonitor`, `Probe` and `ScrapeConfig`
resources, plus the VictoriaMetrics equivalents, and remote-writes to Rush.

## Requirements

Kubernetes: `>=1.27.0-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` |  |
| controller.logLevel | string | `"info"` |  |
| controller.resyncPeriod | string | `"5m"` |  |
| controller.workers | int | `2` |  |
| enableServiceLinks | bool | `false` |  |
| env | list | `[]` | Additional non-secret environment variables for the metrics-agent container. |
| extraLabels | object | `{}` | Labels added to every Prometheus remote-write series. These values override same-named labels supplied by a scrape target so the deployment label remains consistent across workload and metrics-agent self-metrics. |
| fullnameOverride | string | `""` |  |
| global | object | `{"image":{"registry":""},"rush":{"ingestApiKeySecret":{"autoGenerate":false,"key":"api-key","name":"","value":""},"queryApi":{"port":8080,"serviceName":""},"stack":{"enabled":false}}}` | Populated by rush-observability-stack. Standalone installs leave this disabled and must continue to set rushRemoteWrite.url and bearerTokenSecret explicitly. |
| global.image.registry | string | `""` | Optional registry mirror supplied directly or by the stack chart. |
| hostIPC | bool | `false` |  |
| hostNetwork | bool | `false` | Explicitly disable host namespace sharing and service-link environment injection. The agent only needs network access to the Kubernetes API and its configured scrape/remote-write endpoints. |
| hostPID | bool | `false` |  |
| image.digest | string | `""` | Prefer a digest in production. When set, digest takes precedence over tag. |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"ghcr.io/rushobservability/metrics-agent"` |  |
| image.tag | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| nameOverride | string | `""` |  |
| networkPolicy.egress | list | `[]` |  |
| networkPolicy.enabled | bool | `false` |  |
| networkPolicy.ingress | list | `[]` | NetworkPolicy cannot identify the Kubernetes API server or a remote-write destination portably across clusters. Set enabled=true and provide the narrowest ingress/egress rules for your cluster; empty lists are deny-all. See examples/values-secure.yaml. |
| nodeSelector | object | `{}` |  |
| podAnnotations | object | `{}` |  |
| podLabels | object | `{}` |  |
| podSecurityContext.fsGroup | int | `65532` |  |
| podSecurityContext.fsGroupChangePolicy | string | `"OnRootMismatch"` |  |
| podSecurityContext.runAsGroup | int | `65532` |  |
| podSecurityContext.runAsNonRoot | bool | `true` |  |
| podSecurityContext.runAsUser | int | `65532` |  |
| podSecurityContext.seccompProfile.type | string | `"RuntimeDefault"` |  |
| precedence | object | `{"enabled":true}` | The VictoriaMetrics Operator's Prometheus converter must be enabled with VM_ENABLEDPROMETHEUSCONVERTEROWNERREFERENCES=true. See README.md. |
| rbac.create | bool | `true` |  |
| replicaCount | int | `1` | The controller is intentionally single-replica until leader election is implemented. The deployment template rejects values other than one. |
| resources.limits.cpu | string | `"200m"` |  |
| resources.limits.memory | string | `"128Mi"` |  |
| resources.requests.cpu | string | `"20m"` |  |
| resources.requests.memory | string | `"48Mi"` |  |
| rushRemoteWrite.allowAnonymous | bool | `false` | Set true only when the target Rush tenant explicitly has "Require ingest key" disabled. Otherwise bearerTokenSecret.name is required. |
| rushRemoteWrite.bearerTokenSecret.key | string | `"token"` |  |
| rushRemoteWrite.bearerTokenSecret.name | string | `""` | Required when enabled. The key must be a Rush ingest-only API key with the metrics signal enabled, not a query/user or legacy key. |
| rushRemoteWrite.enabled | bool | `false` | The Rust agent publishes its own /metrics payload directly to this URL. |
| rushRemoteWrite.interval | string | `"15s"` |  |
| rushRemoteWrite.tenant | string | `""` | Optional tenant name/id routing hint. It never authorizes access; the ingest-only bearer key must already belong to this tenant. |
| rushRemoteWrite.url | string | `""` |  |
| scrape.enabled | bool | `true` |  |
| scrape.interval | string | `"15s"` |  |
| scrape.timeout | string | `"10s"` |  |
| securityContext.allowPrivilegeEscalation | bool | `false` |  |
| securityContext.capabilities.drop[0] | string | `"ALL"` |  |
| securityContext.privileged | bool | `false` |  |
| securityContext.readOnlyRootFilesystem | bool | `true` |  |
| securityContext.runAsGroup | int | `65532` |  |
| securityContext.runAsNonRoot | bool | `true` |  |
| securityContext.runAsUser | int | `65532` |  |
| selfMetrics | object | `{"enabled":false}` | Optional Prometheus Operator scrape of the agent's /metrics endpoint for clusters that already run a separate Prometheus. This is not required for Rush publishing; use rushRemoteWrite for direct delivery to Rush. |
| service.annotations | object | `{}` |  |
| service.port | int | `7070` |  |
| service.type | string | `"ClusterIP"` |  |
| serviceAccount.annotations | object | `{}` |  |
| serviceAccount.automountServiceAccountToken | bool | `true` | The controller needs a projected Kubernetes token to watch cluster-scoped resources. Kubernetes rotates this token automatically. |
| serviceAccount.create | bool | `true` |  |
| serviceAccount.name | string | `""` |  |
| serviceMonitor.annotations | object | `{}` |  |
| serviceMonitor.enabled | bool | `false` |  |
| serviceMonitor.interval | string | `"30s"` |  |
| serviceMonitor.labels | object | `{}` |  |
| shareProcessNamespace | bool | `false` |  |
| status.livenessPath | string | `"/livez"` |  |
| status.metricsPath | string | `"/metrics"` |  |
| status.readinessPath | string | `"/readyz"` |  |
| terminationGracePeriodSeconds | int | `30` |  |
| tolerations | list | `[]` |  |
| topologySpreadConstraints | list | `[]` |  |
| ui.address | string | `""` | Empty binds the UI to all interfaces on the selected HTTP port. |
| ui.enabled | bool | `true` | The embedded UI is enabled by default and is served through the existing metrics-agent HTTP Service. |
| ui.path | string | `"/ui/"` |  |
| ui.port | string | `""` | Empty uses service.port. Set this only when the UI/server should listen on a different port; the chart will expose that port through the Service. |

## Source Code

* <https://github.com/rushobservability/metrics-agent>
