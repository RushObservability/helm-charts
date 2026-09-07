# rush-observability

![Version: 0.3.2](https://img.shields.io/badge/Version-0.3.2-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.1.25](https://img.shields.io/badge/AppVersion-0.1.25-informational?style=flat-square)

The core Rush platform: Query API, frontend, anomaly processing, and ClickHouse.

> **Most people should install
> [rush-observability-stack](../rush-observability-stack) instead**, which
> installs this chart plus log collection, an OTLP endpoint, and metric
> discovery. Use this chart directly when you already run your own collectors.

Core Rush observability platform with Query API, frontend, anomaly processing, and ClickHouse

**Homepage:** <https://rushobservability.com>

## Install

```bash
helm upgrade --install rush \
  oci://ghcr.io/rushobservability/helm-charts/rush-observability \
  --namespace observability --create-namespace
```

## The values you are most likely to change

| Value | Why |
|---|---|
| `queryApi.config.runtime.environment` | `production` enables fail-closed defaults |
| `queryApi.config.runtime.baseUrl` | Required when environment is `production` |
| `queryApi.config.runtime.trustedProxyCidrs` | Needed for correct client IPs behind an ingress |
| `clickhouse.*` | Operator-managed, standalone, or external — see [ClickHouse](../../docs/clickhouse.md) |
| `imageSecurity.requireDigests` | Recommended for production values files |

Full guides are in [docs/](../../docs/); ready-made values files are in
[examples/](../../examples/).

## Requirements

Kubernetes: `>=1.25.0-0`

| Repository | Name | Version |
|------------|------|---------|
| https://helm.altinity.com | clickhouse | 0.3.x |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| anomalyEngine | object | `{"enabled":false,"env":{"CLICKHOUSE_DATABASE":"observability","RUST_LOG":"rush_api=info"},"extraEnvFrom":[],"extraVolumeMounts":[],"extraVolumes":[],"image":{},"imagePullSecrets":[],"inheritGlobalScheduling":true,"networkPolicy":{"allowExternalHttpsEgress":false,"allowSmtpEgress":false,"enabled":true,"extraEgress":[],"extraIngress":[]},"podAnnotations":{},"podDisruptionBudget":{"enabled":false,"type":"maxUnavailable","value":1},"podLabels":{},"priorityClassName":"","resources":{"limits":{"cpu":"1","memory":"512Mi"},"requests":{"cpu":"100m","memory":"128Mi"}},"rollout":{"minReadySeconds":0,"progressDeadlineSeconds":600,"revisionHistoryLimit":10,"strategy":"Recreate"},"runtimeClassName":"","scheduling":{},"serviceAccount":{"annotations":{},"create":false,"name":""}}` | The anomaly engine evaluates rules and sends notifications. By default the query-api runs it in-process (fine for a single query-api replica). If you scale queryApi.replicas > 1, enable this dedicated single-replica Deployment — the chart then sets RUSH_RUN_ANOMALY_ENGINE=false on the API pods so rules are evaluated exactly once (no duplicate alerts). |
| anomalyEngine.image | object | `{}` | Inherits queryApi.image by default because both workloads run the same Rush API binary. Set only the fields that need to differ for an independent image. |
| anomalyEngine.inheritGlobalScheduling | bool | `true` | ------------------------------------------------------------------- |
| anomalyEngine.rollout | object | `{"minReadySeconds":0,"progressDeadlineSeconds":600,"revisionHistoryLimit":10,"strategy":"Recreate"}` | Recreate prevents duplicate rule evaluation and notification delivery. |
| clickhouse | object | `{"clickhouse":{"affinity":{},"configurationFiles":{"rush_settings.xml":"<clickhouse>\n  <custom_settings_prefixes>rush_</custom_settings_prefixes>\n</clickhouse>\n"},"defaultUser":{"allowExternalAccess":true,"password_secret_name":"rushobs-clickhouse-credentials"},"extraConfig":"{{- include \"rush.clickhouseExtraConfig\" . }}\n","extraUsers":"<clickhouse>\n  <profiles>\n    <default>\n      <max_memory_usage>5368709120</max_memory_usage>\n      <max_memory_usage_for_user>6442450944</max_memory_usage_for_user>\n      <!-- Use the GLOBAL text-index caches (tokens/header/postings/dictionary).\n           These query settings default to 0 in 26.6, which silently gives every\n           query a throwaway per-query cache: misses are counted, nothing is ever\n           retained, and repeated log searches re-read the text index from disk\n           (measured: 0 cache hits ever; enabling these turned identical repeat\n           searches from cold-disk index analysis into cache hits). The global\n           caches are bounded by the text_index_*_cache_size server settings\n           (1+1+2 GiB defaults), SLRU-evicted, and shrink under memory pressure. -->\n      <use_text_index_tokens_cache>1</use_text_index_tokens_cache>\n      <use_text_index_header_cache>1</use_text_index_header_cache>\n      <use_text_index_postings_cache>1</use_text_index_postings_cache>\n      <use_text_index_dictionary_cache>1</use_text_index_dictionary_cache>\n    </default>\n  </profiles>\n</clickhouse>\n","image":{"pullPolicy":"IfNotPresent","repository":"clickhouse/clickhouse-server","tag":"26.6.1.1193"},"logLevel":"information","markCacheSize":2147483648,"nodeSelector":{},"resources":{"limits":{"memory":"8Gi"},"requests":{"cpu":"500m","memory":"8Gi"}},"s3CacheSize":21474836480,"textIndexHeaderCacheSize":536870912,"textIndexPostingsCacheSize":1073741824,"textIndexTokensCacheSize":268435456,"tolerations":[],"topologySpreadConstraints":[],"uncompressedCacheSize":134217728,"users":[{"grants":["GRANT SELECT ON observability.logs","GRANT SELECT ON observability.spans","GRANT SELECT ON observability.spans_by_trace","GRANT SELECT ON observability.services","GRANT SELECT ON observability.metrics_gauge","GRANT SELECT ON observability.metrics_sum","GRANT SELECT ON observability.metrics_histogram","GRANT SELECT ON observability.metrics_exp_histogram","GRANT SELECT ON observability.metrics_summary","GRANT SELECT ON observability.metrics_gauge_1m","GRANT SELECT ON observability.metrics_gauge_1h","GRANT SELECT ON observability.metrics_sum_1m","GRANT SELECT ON observability.metrics_sum_1h","GRANT SELECT ON observability.rum","GRANT SELECT ON observability.rum_replay","GRANT SELECT ON observability.signal_usage","GRANT SELECT ON observability.tenant_usage"],"hostIP":"0.0.0.0/0","name":"rushquery","password_secret_name":"rushobs-clickhouse-read-credentials"}]},"enabled":true,"external":{"credentialsSecret":"","passwordKey":"password","readCredentialsSecret":"","readPasswordKey":"password","readUserKey":"user","url":"","userKey":"user"},"image":{"digest":"","pullPolicy":"IfNotPresent","repository":"clickhouse/clickhouse-server","tag":"26.6.1.1193"},"keeper":{"enabled":false,"nodeSelector":{},"tolerations":[]},"mode":"operator","operator":{"affinity":{},"crdHook":{"affinity":{},"image":{"pullPolicy":"IfNotPresent","repository":"bitnami/kubectl","tag":"1.33.4"},"nodeSelector":{},"tolerations":[]},"enabled":true,"fullnameOverride":"clickhouse-operator","nodeSelector":{},"tolerations":[],"topologySpreadConstraints":[]},"persistence":{"enabled":true,"size":"500Gi","storageClass":""},"replicasCount":1,"service":{"type":"ClusterIP"},"shardsCount":1}` | Full options: https://github.com/Altinity/helm-charts/tree/main/charts/clickhouse |
| clickhouse.clickhouse.configurationFiles | object | `{"rush_settings.xml":"<clickhouse>\n  <custom_settings_prefixes>rush_</custom_settings_prefixes>\n</clickhouse>\n"}` | Custom ClickHouse server configuration files. rush_settings.xml: enables the 'rush_' custom settings prefix so that rush-api can set `rush_tenant_id` per-query for row-level security policies. Without this, getSetting('rush_tenant_id') in row policies will fail with an unknown setting error. Standalone also mounts this explicit file. Operator mode receives the same setting through rush.clickhouseExtraConfig below. |
| clickhouse.clickhouse.extraConfig | string | `"{{- include \"rush.clickhouseExtraConfig\" . }}\n"` | Server config (→ config.d/extra_config.xml) is AUTO-GENERATED from global.storage.s3 by the rush.clickhouseExtraConfig template:   • always emits the `tiered` storage policy (REQUIRED — migrations create     tables with storage_policy='tiered'; without it CREATE TABLE fails);   • when global.storage.s3.enabled, also adds the S3 disk + cache + cold     volume (keyless if no access keys are set). Enable tiering with ONLY the global.storage.s3 block — no hand-written XML. Override this string only for advanced ClickHouse storage customization. |
| clickhouse.clickhouse.extraUsers | string | `"<clickhouse>\n  <profiles>\n    <default>\n      <max_memory_usage>5368709120</max_memory_usage>\n      <max_memory_usage_for_user>6442450944</max_memory_usage_for_user>\n      <!-- Use the GLOBAL text-index caches (tokens/header/postings/dictionary).\n           These query settings default to 0 in 26.6, which silently gives every\n           query a throwaway per-query cache: misses are counted, nothing is ever\n           retained, and repeated log searches re-read the text index from disk\n           (measured: 0 cache hits ever; enabling these turned identical repeat\n           searches from cold-disk index analysis into cache hits). The global\n           caches are bounded by the text_index_*_cache_size server settings\n           (1+1+2 GiB defaults), SLRU-evicted, and shrink under memory pressure. -->\n      <use_text_index_tokens_cache>1</use_text_index_tokens_cache>\n      <use_text_index_header_cache>1</use_text_index_header_cache>\n      <use_text_index_postings_cache>1</use_text_index_postings_cache>\n      <use_text_index_dictionary_cache>1</use_text_index_dictionary_cache>\n    </default>\n  </profiles>\n</clickhouse>\n"` | Per-query / per-user memory ceilings (default profile). Caps one query below the server budget so it fails gracefully (MEMORY_LIMIT_EXCEEDED) instead of OOM-killing the pod; GROUP BY/ORDER BY still spill to disk first. Scale with the memory limit. |
| clickhouse.clickhouse.image | object | `{"pullPolicy":"IfNotPresent","repository":"clickhouse/clickhouse-server","tag":"26.6.1.1193"}` | ClickHouse server image. The 26.6 line adds the direct-read and dictionary-assisted LIKE capabilities used by log search. The Altinity operator runs upstream server images fine. Pin a patch for reproducibility. |
| clickhouse.clickhouse.logLevel | string | `"information"` | Server log level (→ config.d/extra_config.xml <logger><level>). The operator defaults to `debug`, which logs every executed query (full SQL, incl. user search terms) — and Vector tails that back into the logs store. `information` keeps warnings/errors without the per-query spam. Set `debug`/`trace` to troubleshoot. Valid: none|fatal|error|warning|information|debug|trace. |
| clickhouse.clickhouse.markCacheSize | int | `2147483648` | Cache sizes in bytes — right-size with the memory limit above. Referenced by the auto-generated extraConfig below (defaults suit the 8Gi baseline). |
| clickhouse.clickhouse.nodeSelector | object | `{}` | Scheduling for ClickHouse server pods is independent from global.scheduling, allowing a dedicated storage node group. |
| clickhouse.clickhouse.resources | object | `{"limits":{"memory":"8Gi"},"requests":{"cpu":"500m","memory":"8Gi"}}` | Bound ClickHouse memory. With NO limit the server sizes max_server_memory_usage to ~90% of the whole node and the cgroup working-set grows unbounded. A hard limit caps it and makes CH self-throttle instead of being OOM-killed. 8Gi is a conservative baseline — SCALE WITH YOUR NODE and scale the cache sizes + memory profile below proportionally. No CPU limit on purpose (merges/queries benefit from CPU burst). |
| clickhouse.clickhouse.textIndexTokensCacheSize | int | `268435456` | Text-index caches (26.6+): tokens/header/postings deserialized from the logs `text` search index. Queries opt in via the default profile (extraUsers below); sized down from ClickHouse's 1+1+2 GiB defaults to fit the 8Gi baseline. |
| clickhouse.clickhouse.users | list | `[{"grants":["GRANT SELECT ON observability.logs","GRANT SELECT ON observability.spans","GRANT SELECT ON observability.spans_by_trace","GRANT SELECT ON observability.services","GRANT SELECT ON observability.metrics_gauge","GRANT SELECT ON observability.metrics_sum","GRANT SELECT ON observability.metrics_histogram","GRANT SELECT ON observability.metrics_exp_histogram","GRANT SELECT ON observability.metrics_summary","GRANT SELECT ON observability.metrics_gauge_1m","GRANT SELECT ON observability.metrics_gauge_1h","GRANT SELECT ON observability.metrics_sum_1m","GRANT SELECT ON observability.metrics_sum_1h","GRANT SELECT ON observability.rum","GRANT SELECT ON observability.rum_replay","GRANT SELECT ON observability.signal_usage","GRANT SELECT ON observability.tenant_usage"],"hostIP":"0.0.0.0/0","name":"rushquery","password_secret_name":"rushobs-clickhouse-read-credentials"}]` | Tenant-scoped application read identity. Never grant this user access to config_* or audit_events; strict row policies are installed by query-api. |
| clickhouse.enabled | bool | `true` | `enabled` controls the bundled Altinity chart dependency. Keep it true for operator mode. Set it false for standalone or external mode so the operator-managed ClickHouseInstallation is not rendered as well. |
| clickhouse.external.readCredentialsSecret | string | `""` | Distinct SELECT-only identity. The external ClickHouse administrator must grant it SELECT only on telemetry tables and let query-api own strict row policies. |
| clickhouse.keeper.nodeSelector | object | `{}` | Keeper supports an independent node selector and tolerations. zoneSpread adds its built-in zone topology constraint. |
| clickhouse.mode | string | `"operator"` | Deployment strategy: operator (default), standalone (one StatefulSet), or external (use an existing ClickHouse endpoint and Secret). |
| clickhouse.operator.crdHook | object | `{"affinity":{},"image":{"pullPolicy":"IfNotPresent","repository":"bitnami/kubectl","tag":"1.33.4"},"nodeSelector":{},"tolerations":[]}` | Override the upstream chart's floating kubectl:latest CRD hook. |
| clickhouse.operator.enabled | bool | `true` | Set to false if the Altinity ClickHouse Operator is already installed cluster-wide (e.g. shared by multiple teams or managed separately). Rush will still deploy the ClickHouseInstallation CRD resource; it just won't install the operator Deployment, RBAC, or CRDs again. |
| clickhouse.operator.fullnameOverride | string | `"clickhouse-operator"` | Name applied to the operator's resources (Deployment/pod, RBAC, Secret, ServiceMonitor, dashboards). Without this, the Altinity subchart names them "<release>-operator" (e.g. rushobs-operator). Pin it to "clickhouse-operator" so the operator is recognizable regardless of release name. Set to "" to restore the release-prefixed default. |
| clickhouse.operator.nodeSelector | object | `{}` | Dependency-owned control-plane workload. Configure explicitly when node groups are tainted; it does not inherit global.scheduling. |
| clickhouseStandalone | object | `{"affinity":{},"extraEnvFrom":[],"extraVolumeMounts":[],"extraVolumes":[],"imagePullSecrets":[],"networkPolicy":{"allowExternalHttpsEgress":false,"enabled":true,"extraEgress":[],"extraIngress":[]},"nodeSelector":{},"persistence":{"enabled":true,"size":"500Gi","storageClass":""},"podAnnotations":{},"podDisruptionBudget":{"enabled":false,"type":"maxUnavailable","value":1},"podLabels":{},"podSecurityContext":{"fsGroup":101,"runAsGroup":101,"runAsNonRoot":true,"runAsUser":101,"seccompProfile":{"type":"RuntimeDefault"}},"priorityClassName":"","probes":{"liveness":{"enabled":true,"failureThreshold":3,"initialDelaySeconds":30,"path":"/ping","periodSeconds":20,"successThreshold":1,"timeoutSeconds":5},"readiness":{"enabled":true,"failureThreshold":3,"initialDelaySeconds":10,"path":"/ping","periodSeconds":10,"successThreshold":1,"timeoutSeconds":5},"startup":{"enabled":true,"failureThreshold":60,"initialDelaySeconds":0,"path":"/ping","periodSeconds":5,"successThreshold":1,"timeoutSeconds":5}},"rollout":{"partition":0,"podManagementPolicy":"OrderedReady","revisionHistoryLimit":10,"strategy":"RollingUpdate"},"runtimeClassName":"","serviceAccount":{"annotations":{},"create":false,"name":""},"terminationGracePeriodSeconds":120,"tolerations":[],"topologySpreadConstraints":[]}` | Standalone mode settings. This intentionally supports one ClickHouse pod; replicated ClickHouse still needs Keeper and is better handled by the operator mode. |
| clickhouseStandalone.nodeSelector | object | `{}` | Standalone ClickHouse never inherits global.scheduling. |
| enterprise | object | `{"kubernetesAccess":{"clusterId":"","collectPrivateIp":false,"credentialTtlSeconds":3600,"enabled":false,"extraEnvFrom":[],"extraVolumeMounts":[],"extraVolumes":[],"failurePolicy":"fail_open","gatewayId":"","image":{"digest":"","pullPolicy":"Always","repository":"ghcr.io/rushobservability/kubernetes-access-gateway","tag":"0.1.0"},"imagePullSecrets":[],"inheritGlobalScheduling":true,"internalToken":"","maxResultBytes":262144,"maxSessionBytes":67108864,"networkPolicy":{"allowExternalIngress":false,"allowSameNamespaceIngress":true,"enabled":true,"extraEgress":[],"extraIngress":[]},"podAnnotations":{},"podDisruptionBudget":{"enabled":true,"type":"maxUnavailable","value":1},"podLabels":{},"port":8443,"priorityClassName":"","queryApiUrl":"","rbac":{"createImpersonationRole":false,"manageRoles":false},"replicas":2,"resources":{"limits":{"cpu":"1","memory":"512Mi"},"requests":{"cpu":"100m","memory":"128Mi"}},"retainRawIp":false,"retentionDays":30,"runtimeClassName":"","scheduling":{},"service":{"nodePort":null,"port":443,"type":"ClusterIP"},"serviceAccount":{"annotations":{},"create":true,"name":""},"tenantIds":[],"tls":{"existingSecret":""},"trustedProxyCidrs":[],"upstream":{"caFile":"/var/run/secrets/kubernetes.io/serviceaccount/ca.crt","egressCidrs":["0.0.0.0/0"],"insecure":false,"url":"https://kubernetes.default.svc"}},"license":{"enabled":false,"secret":{"key":"license-key","name":"rush-license"}}}` | ══ Enterprise (commercial, license-gated) ══════════════════════════════ Commercial license configuration used by Query API. Add-on workloads are installed by the rush-observability-stack chart. |
| enterprise.kubernetesAccess | object | `{"clusterId":"","collectPrivateIp":false,"credentialTtlSeconds":3600,"enabled":false,"extraEnvFrom":[],"extraVolumeMounts":[],"extraVolumes":[],"failurePolicy":"fail_open","gatewayId":"","image":{"digest":"","pullPolicy":"Always","repository":"ghcr.io/rushobservability/kubernetes-access-gateway","tag":"0.1.0"},"imagePullSecrets":[],"inheritGlobalScheduling":true,"internalToken":"","maxResultBytes":262144,"maxSessionBytes":67108864,"networkPolicy":{"allowExternalIngress":false,"allowSameNamespaceIngress":true,"enabled":true,"extraEgress":[],"extraIngress":[]},"podAnnotations":{},"podDisruptionBudget":{"enabled":true,"type":"maxUnavailable","value":1},"podLabels":{},"port":8443,"priorityClassName":"","queryApiUrl":"","rbac":{"createImpersonationRole":false,"manageRoles":false},"replicas":2,"resources":{"limits":{"cpu":"1","memory":"512Mi"},"requests":{"cpu":"100m","memory":"128Mi"}},"retainRawIp":false,"retentionDays":30,"runtimeClassName":"","scheduling":{},"service":{"nodePort":null,"port":443,"type":"ClusterIP"},"serviceAccount":{"annotations":{},"create":true,"name":""},"tenantIds":[],"tls":{"existingSecret":""},"trustedProxyCidrs":[],"upstream":{"caFile":"/var/run/secrets/kubernetes.io/serviceaccount/ca.crt","egressCidrs":["0.0.0.0/0"],"insecure":false,"url":"https://kubernetes.default.svc"}}` | Licensed Kubernetes access recording. One switch enables the Query API endpoints and deploys the gateway used by kubectl clients. |
| enterprise.kubernetesAccess.inheritGlobalScheduling | bool | `true` | The gateway proxies Kubernetes API requests and sends bounded records to Query API. Configure a commercial license and cluster identity first. |
| enterprise.kubernetesAccess.queryApiUrl | string | `""` | Leave blank to use the Query API Service installed by this chart. |
| enterprise.kubernetesAccess.rbac | object | `{"createImpersonationRole":false,"manageRoles":false}` | Creating the ClusterRole grants this service account permission to impersonate Kubernetes users and groups. Leave it false when platform administrators provide a narrower existing role binding. |
| enterprise.kubernetesAccess.rbac.manageRoles | bool | `false` | Reconcile saved group-to-role grants into native Kubernetes RBAC. The controller needs bind and escalate privileges, so use a dedicated account. |
| enterprise.kubernetesAccess.service.nodePort | string | `nil` | Leave blank to let Kubernetes choose a NodePort. |
| enterprise.kubernetesAccess.tenantIds | list | `[]` | Tenants permitted to exchange their Rush credentials for this cluster. |
| enterprise.kubernetesAccess.tls.existingSecret | string | `""` | The Secret must contain tls.crt and tls.key. |
| enterprise.kubernetesAccess.trustedProxyCidrs | list | `[]` | Trust only known proxy networks. Never use 0.0.0.0/0. |
| enterprise.kubernetesAccess.upstream.egressCidrs | list | `["0.0.0.0/0"]` | Narrow this to the Kubernetes API endpoint CIDR when possible. |
| enterprise.license | object | `{"enabled":false,"secret":{"key":"license-key","name":"rush-license"}}` | When enabled, query-api reads RUSH_LICENSE_KEY from the named Secret and verifies it offline. Create the secret with your minted license token:   kubectl create secret generic rush-license --from-literal=license-key='<token>' |
| frontend.apiBaseUrl | string | `""` | Public base URL (scheme + host, no trailing slash) of the Rush API as seen from outside the cluster. Surfaced to the UI wherever it shows or reaches the API by its public address — e.g. the CloudWatch ingest endpoint AWS Firehose must POST to. Set this when the public API host differs from where admins load the UI (e.g. internal UI + public ingest endpoint). Empty → the UI uses its own origin. |
| frontend.containerPort | int | `8080` | The Rush frontend image runs nginx as uid 65532 and cannot bind below 1024. The Service targetPort follows this via the named "http" port. |
| frontend.extraEnvFrom | list | `[]` |  |
| frontend.extraVolumeMounts | list | `[]` |  |
| frontend.extraVolumes | list | `[]` |  |
| frontend.image.digest | string | `""` |  |
| frontend.image.pullPolicy | string | `"IfNotPresent"` |  |
| frontend.image.repository | string | `"ghcr.io/rushobservability/frontend"` |  |
| frontend.image.tag | string | `"0.1.6"` |  |
| frontend.imagePullSecrets | list | `[]` |  |
| frontend.inheritGlobalScheduling | bool | `true` | ------------------------------------------------------------------- |
| frontend.networkPolicy.allowSameNamespaceIngress | bool | `true` | Allows same-namespace ingress controllers and port-forward helpers. |
| frontend.networkPolicy.enabled | bool | `true` |  |
| frontend.networkPolicy.extraEgress | list | `[]` |  |
| frontend.networkPolicy.extraIngress | list | `[]` |  |
| frontend.podAnnotations | object | `{}` |  |
| frontend.podDisruptionBudget.enabled | bool | `false` |  |
| frontend.podDisruptionBudget.type | string | `"maxUnavailable"` |  |
| frontend.podDisruptionBudget.value | int | `1` |  |
| frontend.podLabels | object | `{}` |  |
| frontend.priorityClassName | string | `""` |  |
| frontend.probes.liveness.enabled | bool | `true` |  |
| frontend.probes.liveness.failureThreshold | int | `3` |  |
| frontend.probes.liveness.initialDelaySeconds | int | `5` |  |
| frontend.probes.liveness.path | string | `"/"` |  |
| frontend.probes.liveness.periodSeconds | int | `10` |  |
| frontend.probes.liveness.successThreshold | int | `1` |  |
| frontend.probes.liveness.timeoutSeconds | int | `2` |  |
| frontend.probes.readiness.enabled | bool | `true` |  |
| frontend.probes.readiness.failureThreshold | int | `3` |  |
| frontend.probes.readiness.initialDelaySeconds | int | `3` |  |
| frontend.probes.readiness.path | string | `"/"` |  |
| frontend.probes.readiness.periodSeconds | int | `5` |  |
| frontend.probes.readiness.successThreshold | int | `1` |  |
| frontend.probes.readiness.timeoutSeconds | int | `2` |  |
| frontend.probes.startup.enabled | bool | `true` |  |
| frontend.probes.startup.failureThreshold | int | `30` |  |
| frontend.probes.startup.initialDelaySeconds | int | `0` |  |
| frontend.probes.startup.path | string | `"/"` |  |
| frontend.probes.startup.periodSeconds | int | `2` |  |
| frontend.probes.startup.successThreshold | int | `1` |  |
| frontend.probes.startup.timeoutSeconds | int | `2` |  |
| frontend.replicas | int | `1` |  |
| frontend.resources.limits.cpu | string | `"500m"` |  |
| frontend.resources.limits.memory | string | `"256Mi"` |  |
| frontend.resources.requests.cpu | string | `"50m"` |  |
| frontend.resources.requests.memory | string | `"64Mi"` |  |
| frontend.rollout.maxSurge | int | `1` |  |
| frontend.rollout.maxUnavailable | int | `0` |  |
| frontend.rollout.minReadySeconds | int | `0` |  |
| frontend.rollout.progressDeadlineSeconds | int | `600` |  |
| frontend.rollout.revisionHistoryLimit | int | `10` |  |
| frontend.rollout.strategy | string | `"RollingUpdate"` |  |
| frontend.runtimeClassName | string | `""` |  |
| frontend.scheduling | object | `{}` |  |
| frontend.service.port | int | `80` |  |
| frontend.service.type | string | `"ClusterIP"` |  |
| frontend.serviceAccount.annotations | object | `{}` |  |
| frontend.serviceAccount.create | bool | `false` |  |
| frontend.serviceAccount.name | string | `""` |  |
| global | object | `{"extraEnvFrom":[],"extraVolumeMounts":[],"extraVolumes":[],"image":{"registry":""},"imagePullSecrets":[],"podAnnotations":{},"podLabels":{},"priorityClassName":"","runtimeClassName":"","rush":{"ingestApiKeySecret":{"autoGenerate":false,"key":"api-key","name":"","value":""},"queryApiIngressComponents":[]},"scheduling":{"affinity":{},"nodeSelector":{},"tolerations":[],"topologySpreadConstraints":[]},"serviceAccount":{"annotations":{}},"storage":{"s3":{"access_key_id":"","bucket":"rush-clickhouse","enabled":false,"endpoint":"","region":"us-east-1","secret_access_key":""},"tiering":{"logs_move_after_days":7,"metrics_move_after_days":3,"traces_move_after_days":3}}}` | Lives under `global` so ONE block drives both the query-api rush.toml AND the ClickHouse subchart's storage config. (Helm only shares values with subcharts via `global`; the ClickHouse dependency cannot see `queryApi.config`.) Enable S3 tiering with just this block — the chart auto-generates the ClickHouse S3 disk + cold volume (see clickhouse.clickhouse.extraConfig). No hand-written XML. |
| global.image.registry | string | `""` | Optional registry mirror. This replaces an image repository's registry while preserving its path, tag, digest, and pull policy. Example: mirror.example.com or mirror.example.com/dockerhub |
| global.podAnnotations | object | `{}` | Shared pod defaults. Non-empty component values replace shared lists and scalar values; annotations and labels merge with component values winning. |
| global.rush.ingestApiKeySecret | object | `{"autoGenerate":false,"key":"api-key","name":"","value":""}` | The stack chart fills this in so Query API can register the same ingest credential mounted by its collectors. Core-only installs leave it off. |
| global.rush.queryApiIngressComponents | list | `[]` | Component labels allowed to send telemetry to Query API. The umbrella chart fills this with its enabled add-on component identities. |
| global.scheduling | object | `{"affinity":{},"nodeSelector":{},"tolerations":[],"topologySpreadConstraints":[]}` | Shared scheduling defaults for core Rush workloads: Query API, frontend, and anomaly engine. ClickHouse is intentionally independent; use clickhouse.clickhouse/keeper scheduling (or clickhouseStandalone scheduling) for storage-optimized node groups. Component scheduling maps deep-merge over these defaults. Component lists replace these lists. Set a component's inheritGlobalScheduling=false to opt out. |
| helmTests | object | `{"activeDeadlineSeconds":180,"backoffLimit":1,"clickhouseConnectivity":true,"enabled":true,"resources":{"limits":{"cpu":"100m","memory":"64Mi"},"requests":{"cpu":"10m","memory":"16Mi"}}}` | Native `helm test` connectivity checks. Jobs are created only as Helm test hooks and use the query-api image, which already contains curl. |
| imageSecurity.requireDigests | bool | `false` | Recommended for every production values file. When enabled, the chart refuses tag-only first-party Rush workloads. |
| queryApi.auditSpoolPersistence | object | `{"accessModes":["ReadWriteOnce"],"enabled":true,"existingClaim":"","size":"1Gi","storageClass":""}` | Storage for the Query API audit spool. Disable it to use an emptyDir. |
| queryApi.config | object | `{"audit":{"keyId":"primary","previousKeysJson":"","spoolMaxBytes":268435456},"authentication":{"allowAnonymousDefault":false,"loginRateLimit":{"accountPerMinute":10,"ipPerMinute":50},"session":{"absoluteTimeoutSeconds":86400,"idleTimeoutSeconds":1800,"renewalIntervalSeconds":300},"ssoReplayStore":"auto"},"ingest":{"buffer":{"backend":"disk","maxBytes":2147483648,"objectStore":{"bucket":"","credentialsSecret":{"accessKeyKey":"access-key","name":"","secretKeyKey":"secret-key"},"endpoint":"","prefix":"ingest/","region":"us-east-1"}},"limits":{"decodeConcurrency":4,"maxCompressedBytes":8388608,"maxDecompressedBytes":33554432,"maxEntities":200000,"maxLabelNameBytes":256,"maxLabelValueBytes":4096,"maxLabelsPerSeries":128,"maxMetadata":10000,"maxSamples":200000,"maxSeries":20000}},"promql":{"lookbackSecs":300},"retention":{"defaults":{"logsDays":30,"metricsDays":30,"tracesDays":30},"enforcer":{"dryRun":false,"enabled":true,"intervalSeconds":3600},"metrics":[],"traces":[]},"runtime":{"baseUrl":"","environment":"development","extraEnv":{"CLICKHOUSE_DATABASE":"observability","RUST_LOG":"rush_api=info,tower_http=info"},"trustedProxyCidrs":[]},"secrets":{"adminPassword":"","apiKeyHmacSecret":"","auditHmacSecret":"","configEncryptionKey":"","existingSecret":"","sessionHmacSecret":"","ssoTransactionSecret":""},"statsEngine":{"intervalSecs":15}}` | Query API application behavior. Kubernetes workload controls remain at the queryApi level below this block. |
| queryApi.config.audit.keyId | string | `"primary"` | Change keyId whenever auditHmacSecret is deliberately rotated. Supply old keys as a JSON object so historical segments remain verifiable. |
| queryApi.config.authentication.allowAnonymousDefault | bool | `false` | Authentication is fail-closed by default. Anonymous-default is only for local development and leaves /readyz unhealthy in production. |
| queryApi.config.authentication.session | object | `{"absoluteTimeoutSeconds":86400,"idleTimeoutSeconds":1800,"renewalIntervalSeconds":300}` | Browser sessions use a renewable idle deadline plus a hard maximum age. |
| queryApi.config.authentication.ssoReplayStore | string | `"auto"` | One-time OIDC/SAML/setup claims. "auto" uses an in-process store for one replica and ClickHouse KeeperMap for two or more replicas. |
| queryApi.config.ingest.buffer | object | `{"backend":"disk","maxBytes":2147483648,"objectStore":{"bucket":"","credentialsSecret":{"accessKeyKey":"access-key","name":"","secretKeyKey":"secret-key"},"endpoint":"","prefix":"ingest/","region":"us-east-1"}}` | The local disk queue is safe for one API pod. HA API replicas must share an object-store queue and use exactly one dedicated drain worker. |
| queryApi.config.ingest.limits | object | `{"decodeConcurrency":4,"maxCompressedBytes":8388608,"maxDecompressedBytes":33554432,"maxEntities":200000,"maxLabelNameBytes":256,"maxLabelValueBytes":4096,"maxLabelsPerSeries":128,"maxMetadata":10000,"maxSamples":200000,"maxSeries":20000}` | Shared request/decompression/entity budgets for every telemetry protocol. |
| queryApi.config.promql.lookbackSecs | int | `300` | Staleness/lookback window for carrying the last metric value through a range query. Keep it at least as long as the slowest scrape interval. |
| queryApi.config.retention.defaults | object | `{"logsDays":30,"metricsDays":30,"tracesDays":30}` | Signal-wide defaults apply when no more specific rule matches. |
| queryApi.config.retention.enforcer | object | `{"dryRun":false,"enabled":true,"intervalSeconds":3600}` | - serviceName: gateway   retainDays: 60 |
| queryApi.config.retention.metrics | list | `[]` | Metric rules are evaluated in order and may match an exact name, a name regex, labels, or a combination of them. |
| queryApi.config.retention.traces | list | `[]` | - nameRegex: "^(node_|kube_)"   labels: {environment: production}   retainDays: 365 Trace rules may match a service name or one span attribute. |
| queryApi.config.runtime.baseUrl | string | `""` | Required when environment is production. Use the externally reachable HTTPS origin without a trailing path, query, or fragment. |
| queryApi.config.runtime.extraEnv | object | `{"CLICKHOUSE_DATABASE":"observability","RUST_LOG":"rush_api=info,tower_http=info"}` | Additional environment variables passed to Query API and its optional drain worker. |
| queryApi.config.runtime.trustedProxyCidrs | list | `[]` | Forwarded client addresses are ignored unless the direct peer belongs to one of these proxy networks. Use pod/ingress CIDRs, never 0.0.0.0/0. |
| queryApi.config.secrets | object | `{"adminPassword":"","apiKeyHmacSecret":"","auditHmacSecret":"","configEncryptionKey":"","existingSecret":"","sessionHmacSecret":"","ssoTransactionSecret":""}` | Leave generated secrets blank to create them on first install and preserve them across upgrades. Use existingSecret to bring your own Secret. |
| queryApi.config.statsEngine.intervalSecs | int | `15` | Cadence for the internal rush_stats_* gauges. Increase it to reduce the sample volume, while keeping it short enough for rate-based queries. |
| queryApi.drainWorker | object | `{"enabled":false,"extraEnvFrom":[],"extraVolumeMounts":[],"extraVolumes":[],"imagePullSecrets":[],"inheritGlobalScheduling":true,"podAnnotations":{},"podDisruptionBudget":{"enabled":false,"type":"maxUnavailable","value":1},"podLabels":{},"priorityClassName":"","resources":{"limits":{"cpu":"1","memory":"512Mi"},"requests":{"cpu":"100m","memory":"128Mi"}},"rollout":{"minReadySeconds":0,"progressDeadlineSeconds":600,"revisionHistoryLimit":10,"strategy":"Recreate"},"runtimeClassName":"","scheduling":{},"serviceAccount":{"annotations":{},"create":false,"name":""},"terminationGracePeriodSeconds":120}` | Optional singleton workload that drains a shared object-store ingest queue. |
| queryApi.drainWorker.rollout | object | `{"minReadySeconds":0,"progressDeadlineSeconds":600,"revisionHistoryLimit":10,"strategy":"Recreate"}` | Recreate is deliberate: the queue contract allows exactly one drainer. |
| queryApi.extraEnvFrom | list | `[]` |  |
| queryApi.extraVolumeMounts | list | `[]` |  |
| queryApi.extraVolumes | list | `[]` |  |
| queryApi.gracefulShutdown | object | `{"enabled":true}` | The preStop hook makes readiness fail before termination and lets query-api flush in-memory batches plus drain its durable ingest queue. Increase this for large backlogs or a ClickHouse recovery window. |
| queryApi.image.digest | string | `""` |  |
| queryApi.image.pullPolicy | string | `"IfNotPresent"` |  |
| queryApi.image.repository | string | `"mzupan/rush-api"` |  |
| queryApi.image.tag | string | `"0.1.25"` |  |
| queryApi.imagePullSecrets | list | `[]` |  |
| queryApi.ingress | object | `{"annotations":{},"api":{"annotations":{},"enabled":false,"host":"","path":"/","pathType":"Prefix","tls":{"enabled":true,"secretName":""}},"className":"","enabled":false,"frontend":{"enabled":true,"host":"","path":"/","pathType":"Prefix","tls":{"enabled":true,"secretName":""}},"trustedProxyCidrs":[]}` | Optional public entry points. The frontend host also proxies /api, /auth, /prom, and /metrics. Enable the API host only when a separate direct API origin is required. trustedProxyCidrs are merged into the Query API trust list so forwarded client addresses are accepted only from known proxies. |
| queryApi.inheritGlobalScheduling | bool | `true` | ------------------------------------------------------------------- |
| queryApi.integrations | object | `{"argocd":{"enabled":false,"namespace":"argocd"},"cloudwatch":{"enabled":false},"fluxcd":{"enabled":false,"namespace":"flux-system"},"infrastructure":{"tenantNamespaces":{}},"kubernetes":{"clusterWide":false,"enabled":false,"namespaces":[]},"sreAgent":{"enabled":false,"githubApp":{"enabled":false,"tenantRepositories":{}},"internalAuthToken":"","port":8081,"service":{"port":8081}}}` | Query API integrations and their access boundaries. |
| queryApi.integrations.infrastructure | object | `{"tenantNamespaces":{}}` | Operator-owned tenant-to-namespace grants shared by the Kubernetes, Argo CD, and Flux integrations. Missing tenant entries deny access. |
| queryApi.integrations.sreAgent | object | `{"enabled":false,"githubApp":{"enabled":false,"tenantRepositories":{}},"internalAuthToken":"","port":8081,"service":{"port":8081}}` | The core chart does not deploy the agent; the stack chart extends this block with SRE agent workload settings. |
| queryApi.networkPolicy.allowExternalClickHouseEgress | bool | `false` |  |
| queryApi.networkPolicy.allowExternalHttpsEgress | bool | `false` | Broad Internet access is off by default. Enable only for OIDC/SAML discovery, Kubernetes API access, webhooks, or other HTTPS integrations. |
| queryApi.networkPolicy.allowSmtpEgress | bool | `false` |  |
| queryApi.networkPolicy.enabled | bool | `true` | Allows HTTP from this release namespace and restricts egress to DNS plus the ports used for Kubernetes/HTTPS, ClickHouse, SRE-agent, and SMTP. |
| queryApi.networkPolicy.extraEgress | list | `[]` |  |
| queryApi.networkPolicy.extraIngress | list | `[]` |  |
| queryApi.podAnnotations | object | `{}` |  |
| queryApi.podDisruptionBudget.enabled | bool | `false` |  |
| queryApi.podDisruptionBudget.type | string | `"maxUnavailable"` |  |
| queryApi.podDisruptionBudget.value | int | `1` |  |
| queryApi.podLabels | object | `{}` |  |
| queryApi.port | int | `8080` |  |
| queryApi.priorityClassName | string | `""` |  |
| queryApi.probes.liveness.enabled | bool | `true` |  |
| queryApi.probes.liveness.failureThreshold | int | `3` |  |
| queryApi.probes.liveness.initialDelaySeconds | int | `10` |  |
| queryApi.probes.liveness.path | string | `"/healthz"` |  |
| queryApi.probes.liveness.periodSeconds | int | `10` |  |
| queryApi.probes.liveness.successThreshold | int | `1` |  |
| queryApi.probes.liveness.timeoutSeconds | int | `2` |  |
| queryApi.probes.readiness.enabled | bool | `true` |  |
| queryApi.probes.readiness.failureThreshold | int | `3` |  |
| queryApi.probes.readiness.initialDelaySeconds | int | `3` |  |
| queryApi.probes.readiness.path | string | `"/readyz"` |  |
| queryApi.probes.readiness.periodSeconds | int | `5` |  |
| queryApi.probes.readiness.successThreshold | int | `1` |  |
| queryApi.probes.readiness.timeoutSeconds | int | `2` |  |
| queryApi.probes.startup.enabled | bool | `true` |  |
| queryApi.probes.startup.failureThreshold | int | `60` |  |
| queryApi.probes.startup.initialDelaySeconds | int | `0` |  |
| queryApi.probes.startup.path | string | `"/healthz"` |  |
| queryApi.probes.startup.periodSeconds | int | `5` |  |
| queryApi.probes.startup.successThreshold | int | `1` |  |
| queryApi.probes.startup.timeoutSeconds | int | `2` |  |
| queryApi.replicas | int | `1` |  |
| queryApi.resources.limits.cpu | string | `"1"` |  |
| queryApi.resources.limits.memory | string | `"512Mi"` |  |
| queryApi.resources.requests.cpu | string | `"100m"` |  |
| queryApi.resources.requests.memory | string | `"128Mi"` |  |
| queryApi.rollout.maxSurge | int | `1` |  |
| queryApi.rollout.maxUnavailable | int | `0` |  |
| queryApi.rollout.minReadySeconds | int | `0` |  |
| queryApi.rollout.progressDeadlineSeconds | int | `600` |  |
| queryApi.rollout.revisionHistoryLimit | int | `10` |  |
| queryApi.rollout.strategy | string | `"RollingUpdate"` |  |
| queryApi.runtimeClassName | string | `""` |  |
| queryApi.scheduling | object | `{}` |  |
| queryApi.service.port | int | `8080` |  |
| queryApi.service.type | string | `"ClusterIP"` |  |
| queryApi.serviceAccount.annotations | object | `{}` |  |
| queryApi.serviceAccount.create | bool | `true` |  |
| queryApi.serviceAccount.name | string | `""` |  |
| queryApi.terminationGracePeriodSeconds | int | `120` |  |

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Mike Zupan | <mike@zcentric.com> | <https://github.com/mzupan> |

## Source Code

* <https://github.com/RushObservability/helm-charts>
* <https://github.com/RushObservability/query-api>
* <https://github.com/RushObservability/frontend>
