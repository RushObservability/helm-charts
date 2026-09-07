# rush-observability-stack

![Version: 0.2.1](https://img.shields.io/badge/Version-0.2.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.1.25](https://img.shields.io/badge/AppVersion-0.1.25-informational?style=flat-square)

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
| file://../metrics-agent | metricsAgent(metrics-agent) | 0.1.4 |
| file://../rush-observability | rush(rush-observability) | 0.3.1 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| collectors | object | `{"allowAnonymousIngest":false,"mode":"hybrid","otel":{"autoscaling":{"enabled":false,"maxReplicas":10,"minReplicas":2,"targetCPUUtilizationPercentage":70},"configOverride":"","extraEnvFrom":[],"extraVolumeMounts":[],"extraVolumes":[],"image":{"digest":"","pullPolicy":"IfNotPresent","repository":"otel/opentelemetry-collector-contrib","tag":"0.118.0"},"imagePullSecrets":[],"inheritGlobalScheduling":true,"kind":"deployment","networkPolicy":{"allowSameNamespaceIngress":true,"enabled":true,"extraEgress":[],"extraIngress":[]},"podAnnotations":{},"podDisruptionBudget":{"enabled":false,"type":"maxUnavailable","value":1},"podLabels":{},"priorityClassName":"","probes":{"liveness":{"enabled":true,"failureThreshold":3,"initialDelaySeconds":15,"path":"/","periodSeconds":20,"successThreshold":1,"timeoutSeconds":2},"readiness":{"enabled":true,"failureThreshold":3,"initialDelaySeconds":5,"path":"/","periodSeconds":10,"successThreshold":1,"timeoutSeconds":2},"startup":{"enabled":true,"failureThreshold":60,"initialDelaySeconds":0,"path":"/","periodSeconds":5,"successThreshold":1,"timeoutSeconds":2}},"replicas":1,"resources":{"limits":{"cpu":"2","memory":"1Gi"},"requests":{"cpu":"200m","memory":"256Mi"}},"rollout":{"maxSurge":1,"maxUnavailable":0,"minReadySeconds":0,"progressDeadlineSeconds":600,"revisionHistoryLimit":10,"strategy":"RollingUpdate"},"runtimeClassName":"","scheduling":{},"service":{"grpcPort":4317,"httpPort":4318,"type":"ClusterIP"},"serviceAccount":{"annotations":{},"create":false,"name":""},"signals":{"logs":false,"metrics":true,"traces":true}},"vector":{"configOverride":"","extraEnvFrom":[],"extraVolumeMounts":[],"extraVolumes":[],"hostPath":{"varLibDockerContainers":"/var/lib/docker/containers","varLog":"/var/log"},"image":{"digest":"","pullPolicy":"IfNotPresent","repository":"timberio/vector","tag":"0.56.0-distroless-libc"},"imagePullSecrets":[],"inheritGlobalScheduling":true,"mode":"logs","networkPolicy":{"allowExternalHttpsEgress":true,"allowSameNamespaceIngress":true,"enabled":true,"extraEgress":[],"extraIngress":[]},"podAnnotations":{},"podDisruptionBudget":{"enabled":false,"type":"maxUnavailable","value":1},"podLabels":{},"priorityClassName":"","resources":{"limits":{"cpu":"1","memory":"512Mi"},"requests":{"cpu":"100m","memory":"128Mi"}},"rollout":{"maxSurge":0,"maxUnavailable":1,"minReadySeconds":0,"revisionHistoryLimit":10,"strategy":"RollingUpdate"},"runtimeClassName":"","scheduling":{},"serviceAccount":{"annotations":{},"create":true,"name":""}}}` | Telemetry collection. Hybrid means OTel receives traces and metrics while Vector tails Kubernetes logs. Set mode to none to use external collectors. |
| enterprise.mysqlCollector | object | `{"enabled":false,"env":{"COLLECTOR_ENVIRONMENT":"production","COLLECTOR_INCLUDE_ERROR_TEXT":"false","RUST_LOG":"info"},"extraEnvFrom":[],"extraVolumeMounts":[],"extraVolumes":[],"image":{"digest":"","pullPolicy":"IfNotPresent","repository":"mzupan/mysql-collector","tag":"0.1.0"},"imagePullSecrets":[],"inheritGlobalScheduling":true,"networkPolicy":{"enabled":true,"extraEgress":[],"extraIngress":[]},"podAnnotations":{},"podDisruptionBudget":{"enabled":false,"type":"maxUnavailable","value":1},"podLabels":{},"priorityClassName":"","resources":{"limits":{"cpu":"500m","memory":"256Mi"},"requests":{"cpu":"50m","memory":"64Mi"}},"rollout":{"minReadySeconds":0,"progressDeadlineSeconds":600,"revisionHistoryLimit":10,"strategy":"Recreate"},"runtimeClassName":"","scheduling":{},"secret":{"apiKeyKey":"api-key","dsnKey":"dsn","name":"rush-mysql-collector"},"serviceAccount":{"annotations":{},"create":false,"name":""}}` | Paid MySQL diagnostics. Requires rush.enterprise.license and a Secret containing the database DSN and Rush ingest key. |
| enterprise.mysqlCollector.networkPolicy.extraEgress | list | `[]` | Required when NetworkPolicy is enabled. Permit TCP 3306 only to the monitored database CIDR or namespace/pod selector. |
| enterprise.postgresCollector | object | `{"enabled":false,"env":{"COLLECTOR_ENVIRONMENT":"production","RUST_LOG":"info"},"extraEnvFrom":[],"extraVolumeMounts":[],"extraVolumes":[],"image":{"digest":"","pullPolicy":"IfNotPresent","repository":"mzupan/postgres-collector","tag":"0.1.0"},"imagePullSecrets":[],"inheritGlobalScheduling":true,"networkPolicy":{"enabled":true,"extraEgress":[],"extraIngress":[]},"podAnnotations":{},"podDisruptionBudget":{"enabled":false,"type":"maxUnavailable","value":1},"podLabels":{},"priorityClassName":"","resources":{"limits":{"cpu":"500m","memory":"256Mi"},"requests":{"cpu":"50m","memory":"64Mi"}},"rollout":{"minReadySeconds":0,"progressDeadlineSeconds":600,"revisionHistoryLimit":10,"strategy":"Recreate"},"runtimeClassName":"","scheduling":{},"secret":{"apiKeyKey":"api-key","dsnKey":"dsn","name":"rush-pg-collector"},"serviceAccount":{"annotations":{},"create":false,"name":""}}` | Paid PostgreSQL diagnostics. Requires rush.enterprise.license and a Secret containing the database DSN and Rush ingest key. |
| global | object | `{"extraEnvFrom":[],"extraVolumeMounts":[],"extraVolumes":[],"image":{"registry":""},"imagePullSecrets":[],"podAnnotations":{},"podLabels":{},"priorityClassName":"","runtimeClassName":"","rush":{"ingestApiKeySecret":{"autoGenerate":true,"key":"api-key","name":"","value":""},"queryApi":{"port":8080,"serviceName":""},"queryApiIngressComponents":["otel-collector","vector","postgres-collector","mysql-collector","metrics-agent"],"stack":{"enabled":true}},"scheduling":{"affinity":{},"nodeSelector":{},"tolerations":[],"topologySpreadConstraints":[]},"serviceAccount":{"annotations":{}}}` | Shared Kubernetes defaults inherited by application and collector workloads. |
| global.image.registry | string | `""` | Optional registry mirror for images rendered by the Rush charts. Example: mirror.example.com or mirror.example.com/dockerhub |
| global.rush | object | `{"ingestApiKeySecret":{"autoGenerate":true,"key":"api-key","name":"","value":""},"queryApi":{"port":8080,"serviceName":""},"queryApiIngressComponents":["otel-collector","vector","postgres-collector","mysql-collector","metrics-agent"],"stack":{"enabled":true}}` | Stack plumbing. Leave stack, ingress component names, and service details unchanged. ingestApiKeySecret may point to an externally managed Secret. |
| global.rush.ingestApiKeySecret | object | `{"autoGenerate":true,"key":"api-key","name":"","value":""}` | Rush ingest-only API key shared by Query API, OTel Collector, Vector, and metrics-agent. By default Helm generates and registers it automatically. |
| global.rush.ingestApiKeySecret.autoGenerate | bool | `true` | Generate <release>-ingest on first install and preserve it on upgrades. Set false only for anonymous ingest or when no authenticated add-on is used. |
| global.rush.ingestApiKeySecret.name | string | `""` | Set a name to use an externally managed Secret instead. |
| global.rush.ingestApiKeySecret.value | string | `""` | Optional explicit key. This creates the chart-managed Secret and takes precedence over automatic generation. It is stored in release history. |
| global.rush.queryApi.serviceName | string | `""` | Blank resolves to <release>-query-api. |
| metricsAgent | object | `{"enabled":true,"extraLabels":{"env":"dev"},"nameOverride":"metrics-agent","rushRemoteWrite":{"allowAnonymous":false,"enabled":true,"url":""}}` | Prometheus-compatible target discovery and remote write. |
| rush | object | `{"clickhouse":{"clickhouse":{"resources":{"limits":{"memory":"4Gi"},"requests":{"memory":"2Gi"}}},"enabled":false,"external":{"credentialsSecret":"","passwordKey":"password","url":"","userKey":"user"},"fullnameOverride":"","mode":"standalone"},"clickhouseStandalone":{"persistence":{"enabled":true,"size":"20Gi","storageClass":""}},"enterprise":{"license":{"enabled":false,"secret":{"key":"license-key","name":"rush-license"}}},"frontend":{"replicas":1,"resources":{"limits":{"cpu":"500m","memory":"256Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}},"imageSecurity":{"requireDigests":false},"queryApi":{"config":{"promql":{"lookbackSecs":300},"retention":{"defaults":{"logsDays":30,"metricsDays":30,"tracesDays":30},"enforcer":{"dryRun":false,"enabled":true,"intervalSeconds":3600},"metrics":[],"traces":[]},"runtime":{"baseUrl":"http://localhost:8080","environment":"development"},"secrets":{"existingSecret":""},"statsEngine":{"intervalSecs":15}},"ingress":{"className":"","enabled":false,"frontend":{"host":"","tls":{"enabled":true,"secretName":""}}},"integrations":{"argocd":{"enabled":false,"namespace":"argocd"},"fluxcd":{"enabled":false,"namespace":"flux-system"},"kubernetes":{"enabled":false},"sreAgent":{"enabled":false,"env":{"RUST_LOG":"sre_agent=info,tower_http=info"},"extraEnvFrom":[],"extraVolumeMounts":[],"extraVolumes":[],"githubApp":{"apiUrl":"https://api.github.com","appId":"","cacheSizeLimit":"1Gi","enabled":false,"privateKeySecret":{"key":"private-key.pem","name":""},"tenantRepositories":{}},"image":{"digest":"","pullPolicy":"IfNotPresent","repository":"ghcr.io/rushobservability/sre-agent","tag":"0.1.2"},"imagePullSecrets":[],"inheritGlobalScheduling":true,"internalAuthToken":"","kube":{"allowClusterScopedForAdmins":false,"tenantNamespaces":{}},"networkPolicy":{"allowExternalHttpsEgress":false,"enabled":true,"extraEgress":[],"extraIngress":[]},"podAnnotations":{},"podDisruptionBudget":{"enabled":false,"type":"maxUnavailable","value":1},"podLabels":{},"podSecurityContext":{"fsGroup":65532,"fsGroupChangePolicy":"OnRootMismatch","runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}},"port":8081,"priorityClassName":"","probes":{"liveness":{"enabled":true,"failureThreshold":3,"initialDelaySeconds":10,"path":"/healthz","periodSeconds":10,"successThreshold":1,"timeoutSeconds":2},"readiness":{"enabled":true,"failureThreshold":3,"initialDelaySeconds":3,"path":"/healthz","periodSeconds":5,"successThreshold":1,"timeoutSeconds":2},"startup":{"enabled":true,"failureThreshold":60,"initialDelaySeconds":0,"path":"/healthz","periodSeconds":5,"successThreshold":1,"timeoutSeconds":2}},"replicas":1,"resources":{"limits":{"cpu":"1","memory":"512Mi"},"requests":{"cpu":"100m","memory":"128Mi"}},"rollout":{"maxSurge":1,"maxUnavailable":0,"minReadySeconds":0,"progressDeadlineSeconds":600,"revisionHistoryLimit":10,"strategy":"RollingUpdate"},"runtimeClassName":"","scheduling":{},"service":{"port":8081,"type":"ClusterIP"},"serviceAccount":{"annotations":{},"create":true,"name":""}}},"replicas":1,"resources":{"limits":{"cpu":"1","memory":"512Mi"},"requests":{"cpu":"100m","memory":"128Mi"}}}}` | Start here. `rush` contains the API, UI, ClickHouse, ingress, and integration settings. The stack defaults are sized for a development or evaluation cluster: standalone ClickHouse, a 20 GiB volume, and localhost access. Production examples are documented in docs/getting-started.md.  Most installations only change:   rush.queryApi, rush.clickhouse,   global.scheduling, collectors, and metricsAgent.extraLabels. |
| rush.clickhouse.enabled | bool | `false` | Helm dependency gate. Keep false for standalone/external and set true with mode=operator. |
| rush.queryApi.integrations.sreAgent.enabled | bool | `false` | Optional investigation service. Provider credentials remain in Query API; the agent receives only short-lived requests and its internal token. |

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Mike Zupan | <mike@zcentric.com> | <https://github.com/mzupan> |

## Source Code

* <https://github.com/RushObservability/helm-charts>
