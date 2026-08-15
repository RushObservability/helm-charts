{{- define "rush.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rush.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/* Stable component resource name. */}}
{{- define "rush.componentName" -}}
{{- printf "%s-%s" (include "rush.fullname" .root) .component | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Immutable labels used by workload selectors and pod templates. */}}
{{- define "rush.selectorLabels" -}}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end -}}

{{/* Complete metadata labels for a component resource. */}}
{{- define "rush.componentLabels" -}}
app.kubernetes.io/component: {{ .component }}
{{ include "rush.labels" .root }}
{{- end -}}

{{/* Canonical in-cluster service endpoints. Always use Service ports here. */}}
{{- define "rush.queryApiServiceName" -}}
{{- include "rush.componentName" (dict "root" . "component" "query-api") -}}
{{- end -}}

{{- define "rush.queryApiUrl" -}}
{{- printf "http://%s:%v" (include "rush.queryApiServiceName" .) .Values.queryApi.service.port -}}
{{- end -}}

{{/* Optional stack-managed ingest key that Query API registers at startup. */}}
{{- define "rush.bootstrapIngestApiKeySecretName" -}}
{{- $config := .Values.global.rush.ingestApiKeySecret | default dict -}}
{{- if ($config.name | default "") -}}
{{- $config.name -}}
{{- else if or ($config.autoGenerate | default false) ($config.value | default "") -}}
{{- printf "%s-ingest" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "rush.sreAgentServiceName" -}}
{{- include "rush.componentName" (dict "root" . "component" "sre-agent") -}}
{{- end -}}

{{- define "rush.sreAgentUrl" -}}
{{- printf "http://%s:%v" (include "rush.sreAgentServiceName" .) .Values.global.sreAgent.service.port -}}
{{- end -}}

{{/* ClickHouse writer connection environment for Rush application workloads. */}}
{{- define "rush.clickhouseWriteEnv" -}}
- name: CLICKHOUSE_URL
  value: {{ include "rush.clickhouseUrl" . | quote }}
- name: CLICKHOUSE_USER
  valueFrom:
    secretKeyRef:
      name: {{ include "rush.clickhouseCredentialsSecret" . }}
      key: {{ include "rush.clickhouseUserKey" . }}
- name: CLICKHOUSE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "rush.clickhouseCredentialsSecret" . }}
      key: {{ include "rush.clickhousePasswordKey" . }}
{{- end -}}

{{/* Tenant-scoped SELECT-only ClickHouse identity. */}}
{{- define "rush.clickhouseReadEnv" -}}
- name: CLICKHOUSE_READ_USER
  valueFrom:
    secretKeyRef:
      name: {{ include "rush.clickhouseReadCredentialsSecret" . }}
      key: {{ include "rush.clickhouseReadUserKey" . }}
- name: CLICKHOUSE_READ_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "rush.clickhouseReadCredentialsSecret" . }}
      key: {{ include "rush.clickhouseReadPasswordKey" . }}
{{- end -}}

{{/* Baseline hardened container policy for first-party stateless workloads. */}}
{{- define "rush.hardenedContainerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end -}}

{{/*
Layer shared Rush-workload scheduling defaults with a component override.

Maps (nodeSelector and affinity) are deep-merged, with component keys winning.
Lists (tolerations and topologySpreadConstraints) are replaced when the
component supplies that key. Set inheritGlobalScheduling=false on a workload to
ignore every global scheduling default. ClickHouse is intentionally excluded;
its operator/keeper and standalone values remain independent.
*/}}
{{- define "rush.workloadScheduling" -}}
{{- $root := .root -}}
{{- $workload := .workload | default dict -}}
{{- $global := $root.Values.global.scheduling | default dict -}}
{{- $local := $workload.scheduling | default dict -}}
{{- $inherit := true -}}
{{- if hasKey $workload "inheritGlobalScheduling" -}}
{{- $inherit = $workload.inheritGlobalScheduling -}}
{{- end -}}

{{- $nodeSelector := dict -}}
{{- $affinity := dict -}}
{{- $tolerations := list -}}
{{- $topologySpreadConstraints := list -}}
{{- if $inherit -}}
{{- $nodeSelector = deepCopy ($global.nodeSelector | default dict) -}}
{{- $affinity = deepCopy ($global.affinity | default dict) -}}
{{- $tolerations = deepCopy ($global.tolerations | default list) -}}
{{- $topologySpreadConstraints = deepCopy ($global.topologySpreadConstraints | default list) -}}
{{- end -}}

{{- if hasKey $local "nodeSelector" -}}
{{- $nodeSelector = mergeOverwrite $nodeSelector (deepCopy ($local.nodeSelector | default dict)) -}}
{{- end -}}
{{- if hasKey $local "affinity" -}}
{{- $affinity = mergeOverwrite $affinity (deepCopy ($local.affinity | default dict)) -}}
{{- end -}}
{{- if hasKey $local "tolerations" -}}
{{- $tolerations = deepCopy ($local.tolerations | default list) -}}
{{- end -}}
{{- if hasKey $local "topologySpreadConstraints" -}}
{{- $topologySpreadConstraints = deepCopy ($local.topologySpreadConstraints | default list) -}}
{{- end -}}

{{- with $nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $topologySpreadConstraints }}
topologySpreadConstraints:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/* Merge global and component pod annotations. */}}
{{- define "rush.podAnnotations" -}}
{{- $global := deepCopy (.root.Values.global.podAnnotations | default dict) -}}
{{- $local := deepCopy (.workload.podAnnotations | default dict) -}}
{{- $merged := mergeOverwrite $global $local -}}
{{- with $merged }}{{ toYaml . }}{{- end -}}
{{- end -}}

{{/* Merge global and component pod labels without replacing selector labels. */}}
{{- define "rush.podLabels" -}}
{{- $global := deepCopy (.root.Values.global.podLabels | default dict) -}}
{{- $local := deepCopy (.workload.podLabels | default dict) -}}
{{- $merged := mergeOverwrite $global $local -}}
{{- $_ := unset $merged "app.kubernetes.io/component" -}}
{{- $_ := unset $merged "app.kubernetes.io/instance" -}}
{{- with $merged }}{{ toYaml . }}{{- end -}}
{{- end -}}

{{/* Shared pod-spec options with non-empty component values taking priority. */}}
{{- define "rush.podSpecOptions" -}}
{{- $root := .root -}}
{{- $workload := .workload | default dict -}}
{{- $pullSecrets := $root.Values.global.imagePullSecrets | default list -}}
{{- if $workload.imagePullSecrets }}{{- $pullSecrets = $workload.imagePullSecrets -}}{{- end -}}
{{- $priority := $workload.priorityClassName | default $root.Values.global.priorityClassName -}}
{{- $runtime := $workload.runtimeClassName | default $root.Values.global.runtimeClassName -}}
{{- with $pullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $priority }}
priorityClassName: {{ . | quote }}
{{- end }}
{{- with $runtime }}
runtimeClassName: {{ . | quote }}
{{- end }}
{{- end -}}

{{/* Shared envFrom list; non-empty component values replace the global list. */}}
{{- define "rush.extraEnvFrom" -}}
{{- $items := .root.Values.global.extraEnvFrom | default list -}}
{{- if .workload.extraEnvFrom }}{{- $items = .workload.extraEnvFrom -}}{{- end -}}
{{- with $items }}
envFrom:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}

{{/* Shared extra volume mounts; non-empty component values replace globals. */}}
{{- define "rush.extraVolumeMounts" -}}
{{- $items := .root.Values.global.extraVolumeMounts | default list -}}
{{- if .workload.extraVolumeMounts }}{{- $items = .workload.extraVolumeMounts -}}{{- end -}}
{{- with $items }}{{ toYaml . }}{{- end -}}
{{- end -}}

{{/* Shared extra volumes; non-empty component values replace globals. */}}
{{- define "rush.extraVolumes" -}}
{{- $items := .root.Values.global.extraVolumes | default list -}}
{{- if .workload.extraVolumes }}{{- $items = .workload.extraVolumes -}}{{- end -}}
{{- with $items }}{{ toYaml . }}{{- end -}}
{{- end -}}

{{/* Resolve a component's generated, existing, or default ServiceAccount. */}}
{{- define "rush.serviceAccountName" -}}
{{- $sa := .workload.serviceAccount | default dict -}}
{{- if $sa.name -}}
{{- $sa.name -}}
{{- else if $sa.create -}}
{{- include "rush.componentName" (dict "root" .root "component" .component) -}}
{{- else -}}
default
{{- end -}}
{{- end -}}

{{/* Merge shared and component ServiceAccount annotations. */}}
{{- define "rush.serviceAccountAnnotations" -}}
{{- $global := deepCopy (.root.Values.global.serviceAccount.annotations | default dict) -}}
{{- $local := deepCopy (.workload.serviceAccount.annotations | default dict) -}}
{{- $merged := mergeOverwrite $global $local -}}
{{- with $merged }}{{ toYaml . }}{{- end -}}
{{- end -}}

{{/* Render one optional component ServiceAccount. */}}
{{- define "rush.serviceAccount" -}}
{{- if .workload.serviceAccount.create }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "rush.serviceAccountName" . }}
  labels:
    {{- include "rush.componentLabels" (dict "root" .root "component" .component) | nindent 4 }}
  {{- with (include "rush.serviceAccountAnnotations" .) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
automountServiceAccountToken: false
{{- end }}
{{- end -}}

{{/* Public browser origin used by SSO, links, and CSRF validation. */}}
{{- define "rush.effectiveBaseUrl" -}}
{{- if .Values.queryApi.baseUrl -}}
{{- trimSuffix "/" .Values.queryApi.baseUrl -}}
{{- else if and .Values.ingress.enabled .Values.ingress.frontend.enabled .Values.ingress.frontend.host -}}
{{- $scheme := ternary "https" "http" .Values.ingress.frontend.tls.enabled -}}
{{- printf "%s://%s" $scheme .Values.ingress.frontend.host -}}
{{- end -}}
{{- end -}}

{{/* Explicit trusted proxies plus ingress-controller CIDRs. */}}
{{- define "rush.trustedProxyCidrs" -}}
{{- concat (.Values.queryApi.trustedProxyCidrs | default list) (.Values.ingress.trustedProxyCidrs | default list) | uniq | join "," -}}
{{- end -}}

{{/* Configurable Deployment rollout policy. Singleton workers use Recreate. */}}
{{- define "rush.deploymentRollout" -}}
{{- $rollout := .rollout -}}
strategy:
  type: {{ $rollout.strategy }}
  {{- if eq $rollout.strategy "RollingUpdate" }}
  rollingUpdate:
    maxUnavailable: {{ $rollout.maxUnavailable }}
    maxSurge: {{ $rollout.maxSurge }}
  {{- end }}
minReadySeconds: {{ $rollout.minReadySeconds }}
progressDeadlineSeconds: {{ $rollout.progressDeadlineSeconds }}
revisionHistoryLimit: {{ $rollout.revisionHistoryLimit }}
{{- end -}}

{{/* Configurable DaemonSet rollout policy for node-local collectors. */}}
{{- define "rush.daemonSetRollout" -}}
{{- $rollout := .rollout -}}
updateStrategy:
  type: {{ $rollout.strategy }}
  {{- if eq $rollout.strategy "RollingUpdate" }}
  rollingUpdate:
    maxUnavailable: {{ $rollout.maxUnavailable }}
    maxSurge: {{ $rollout.maxSurge }}
  {{- end }}
minReadySeconds: {{ $rollout.minReadySeconds }}
revisionHistoryLimit: {{ $rollout.revisionHistoryLimit }}
{{- end -}}

{{/* HTTP startup/readiness/liveness probe body. The caller owns the probe key. */}}
{{- define "rush.httpProbe" -}}
{{- $probe := .probe -}}
httpGet:
  path: {{ $probe.path }}
  port: {{ .port }}
  scheme: {{ $probe.scheme | default "HTTP" }}
initialDelaySeconds: {{ $probe.initialDelaySeconds }}
periodSeconds: {{ $probe.periodSeconds }}
timeoutSeconds: {{ $probe.timeoutSeconds }}
failureThreshold: {{ $probe.failureThreshold }}
successThreshold: {{ $probe.successThreshold }}
{{- end -}}

{{/* Shared durable ingest-buffer contract for API pods and the drain worker. */}}
{{- define "rush.queryApiBufferEnv" -}}
{{- $root := .root -}}
{{- $buffer := $root.Values.queryApi.buffer -}}
{{- $drainOnly := .drainOnly | default false -}}
- name: RUSH_SPOOL_MAX_BYTES
  value: {{ $buffer.maxBytes | int64 | quote }}
- name: RUSH_BUFFER_BACKEND
  value: {{ $buffer.backend | quote }}
- name: RUSH_BUFFER_REQUIRE_OBJECT_STORE
  value: {{ eq $buffer.backend "object_store" | quote }}
- name: RUSH_EXPECTED_QUERY_API_REPLICAS
  value: {{ $root.Values.queryApi.replicas | quote }}
- name: RUSH_RUN_REPLAYER
  value: {{ or $drainOnly (not $buffer.drainWorker.enabled) | quote }}
{{- if $drainOnly }}
- name: RUSH_DRAIN_WORKER_ONLY
  value: "true"
{{- end }}
{{- if eq $buffer.backend "object_store" }}
- name: RUSH_BUFFER_S3_ENDPOINT
  value: {{ $buffer.objectStore.endpoint | quote }}
- name: RUSH_BUFFER_S3_BUCKET
  value: {{ $buffer.objectStore.bucket | quote }}
- name: RUSH_BUFFER_S3_PREFIX
  value: {{ $buffer.objectStore.prefix | quote }}
- name: RUSH_BUFFER_S3_REGION
  value: {{ $buffer.objectStore.region | quote }}
- name: RUSH_BUFFER_S3_ACCESS_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $buffer.objectStore.credentialsSecret.name }}
      key: {{ $buffer.objectStore.credentialsSecret.accessKeyKey }}
- name: RUSH_BUFFER_S3_SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: {{ $buffer.objectStore.credentialsSecret.name }}
      key: {{ $buffer.objectStore.credentialsSecret.secretKeyKey }}
{{- end }}
{{- end -}}

{{/* Render a policy/v1 PodDisruptionBudget for one component. */}}
{{- define "rush.podDisruptionBudget" -}}
{{- if .pdb.enabled }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "rush.componentName" (dict "root" .root "component" (printf "%s-pdb" .component)) }}
  labels:
    {{- include "rush.componentLabels" (dict "root" .root "component" .component) | nindent 4 }}
spec:
  {{ .pdb.type }}: {{ .pdb.value }}
  selector:
    matchLabels:
      {{- include "rush.selectorLabels" (dict "root" .root "component" .component) | nindent 6 }}
{{- end }}
{{- end -}}

{{/*
Render an immutable OCI digest when supplied, otherwise an explicit tag. The
digest is deliberately separate from repository so values remain readable and
policy validation can distinguish immutable production configuration.
*/}}
{{- define "rush.image" -}}
{{- $image := .image -}}
{{- $repository := required "image.repository is required" $image.repository -}}
{{- $digest := default "" $image.digest -}}
{{- if $digest -}}
{{- if not (regexMatch "^sha256:[0-9a-f]{64}$" $digest) -}}
{{- fail (printf "invalid image digest for %s: expected sha256 followed by 64 lowercase hex characters" $repository) -}}
{{- end -}}
{{- printf "%s@%s" $repository $digest -}}
{{- else -}}
{{- $tag := default .defaultTag $image.tag -}}
{{- if or (not $tag) (eq $tag "latest") (hasPrefix "latest-" $tag) -}}
{{- fail (printf "floating or empty image tag is not allowed for %s" $repository) -}}
{{- end -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}
{{- end -}}

{{/*
ClickHouse service DNS name inside the cluster. The Altinity subchart and the
standalone StatefulSet intentionally use the same service name.
*/}}
{{- define "rush.clickhouseService" -}}
{{- if eq .Values.clickhouse.mode "operator" -}}
{{- $name := .Values.clickhouse.fullnameOverride -}}
{{- if not $name -}}
{{- if contains "clickhouse" .Release.Name -}}
{{- $name = .Release.Name -}}
{{- else -}}
{{- $name = printf "%s-clickhouse" .Release.Name -}}
{{- end -}}
{{- end -}}
{{- printf "%s-service" $name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "clickhouse-%s-clickhouse" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/* URL used by Rush workloads to reach ClickHouse. */}}
{{- define "rush.clickhouseUrl" -}}
{{- if eq .Values.clickhouse.mode "external" -}}
{{- required "clickhouse.external.url is required when clickhouse.mode=external" .Values.clickhouse.external.url -}}
{{- else -}}
http://{{ include "rush.clickhouseService" . }}:8123
{{- end -}}
{{- end -}}

{{/* Secret containing ClickHouse credentials for Rush workloads. */}}
{{- define "rush.clickhouseCredentialsSecret" -}}
{{- if eq .Values.clickhouse.mode "external" -}}
{{- required "clickhouse.external.credentialsSecret is required when clickhouse.mode=external" .Values.clickhouse.external.credentialsSecret -}}
{{- else -}}
rushobs-clickhouse-credentials
{{- end -}}
{{- end -}}

{{- define "rush.clickhouseUserKey" -}}
{{- if eq .Values.clickhouse.mode "external" }}{{ .Values.clickhouse.external.userKey }}{{ else }}user{{ end -}}
{{- end -}}

{{- define "rush.clickhousePasswordKey" -}}
{{- if eq .Values.clickhouse.mode "external" }}{{ .Values.clickhouse.external.passwordKey }}{{ else }}password{{ end -}}
{{- end -}}

{{/* SELECT-only identity used for tenant-scoped telemetry reads. */}}
{{- define "rush.clickhouseReadCredentialsSecret" -}}
{{- if eq .Values.clickhouse.mode "external" -}}
{{- required "clickhouse.external.readCredentialsSecret is required when clickhouse.mode=external" .Values.clickhouse.external.readCredentialsSecret -}}
{{- else -}}
rushobs-clickhouse-read-credentials
{{- end -}}
{{- end -}}

{{- define "rush.clickhouseReadUserKey" -}}
{{- if eq .Values.clickhouse.mode "external" }}{{ .Values.clickhouse.external.readUserKey }}{{ else }}user{{ end -}}
{{- end -}}

{{- define "rush.clickhouseReadPasswordKey" -}}
{{- if eq .Values.clickhouse.mode "external" }}{{ .Values.clickhouse.external.readPasswordKey }}{{ else }}password{{ end -}}
{{- end -}}

{{/*
Build the ClickHouse S3 disk endpoint from the single `global.storage.s3` config.
- Custom endpoint set (MinIO/RustFS/etc.): path-style "<endpoint>/<bucket>/clickhouse/"
- Blank endpoint (AWS native): virtual-hosted "https://<bucket>.s3.<region>.amazonaws.com/clickhouse/"
*/}}
{{- define "rush.s3Endpoint" -}}
{{- $s3 := .Values.global.storage.s3 -}}
{{- if $s3.endpoint -}}
{{- printf "%s/%s/clickhouse/" (trimSuffix "/" $s3.endpoint) $s3.bucket -}}
{{- else -}}
{{- printf "https://%s.s3.%s.amazonaws.com/clickhouse/" $s3.bucket $s3.region -}}
{{- end -}}
{{- end -}}

{{/*
Generate the entire ClickHouse extra server config (config.d/extra_config.xml) from
the single source of truth `global.storage.s3`. This is what lets users enable S3
tiering with ONLY the rushConfig/global.storage.s3 block — the chart wires the
ClickHouse storage_configuration (S3 disk + cache + cold volume) automatically; no
hand-written XML. When s3.enabled is false, only the local-disk `tiered` policy is
emitted (required so tables created with storage_policy='tiered' don't fail).

Invoked from clickhouse.clickhouse.extraConfig, which the Altinity subchart renders
through `tpl`. Reads `.Values.global.storage` (shared with subcharts via global) and
`.Values.clickhouse.*` cache sizes (subchart-scoped).
*/}}
{{- define "rush.clickhouseExtraConfig" -}}
{{- $s3 := .Values.global.storage.s3 -}}
<clickhouse>
  <!-- Required for the per-query rush_tenant_id row-policy setting. This helper
       is rendered into config.d in both operator and standalone modes. -->
  <custom_settings_prefixes>rush_</custom_settings_prefixes>
  <!-- KeeperMap is the linearizable one-time-claim store used by SSO when
       query-api has multiple replicas. The engine remains unused for a
       single-replica deployment unless queryApi.ssoReplayStore=keeper. -->
  <keeper_map_path_prefix>/rush</keeper_map_path_prefix>
  <!-- The operator's default log level is `debug`, which writes every executed
       query (full SQL, including user search terms) to the server log as
       `<Debug> executeQuery`. Vector tails that log back into the `logs` table,
       so each search re-ingested its own term and became searchable. `information`
       keeps warnings/errors but drops the per-query debug spam. Override via
       clickhouse.clickhouse.logLevel. -->
  <logger>
    <level>{{ .Values.clickhouse.logLevel | default "information" }}</level>
  </logger>
  <mark_cache_size>{{ .Values.clickhouse.markCacheSize | int64 }}</mark_cache_size>
  <uncompressed_cache_size>{{ .Values.clickhouse.uncompressedCacheSize | int64 }}</uncompressed_cache_size>
  <!-- Text-index cache budgets (26.6+). ClickHouse defaults are 1+1+2 GiB — too
       large next to the 2 GiB mark cache inside the 8Gi memory baseline. Queries
       only use these global caches because the default profile (extraUsers) sets
       use_text_index_{tokens,header,postings,dictionary}_cache=1. -->
  <text_index_tokens_cache_size>{{ .Values.clickhouse.textIndexTokensCacheSize | int64 }}</text_index_tokens_cache_size>
  <text_index_header_cache_size>{{ .Values.clickhouse.textIndexHeaderCacheSize | int64 }}</text_index_header_cache_size>
  <text_index_postings_cache_size>{{ .Values.clickhouse.textIndexPostingsCacheSize | int64 }}</text_index_postings_cache_size>
  <storage_configuration>
    {{- if $s3.enabled }}
    <disks>
      <s3>
        <type>s3</type>
        <endpoint>{{ include "rush.s3Endpoint" . }}</endpoint>
        {{- if $s3.access_key_id }}
        <access_key_id>{{ $s3.access_key_id }}</access_key_id>
        <secret_access_key>{{ $s3.secret_access_key }}</secret_access_key>
        <use_environment_credentials>0</use_environment_credentials>
        {{- else }}
        <!-- Keyless: credentials come from the pod's IAM role (IRSA / EKS Pod Identity) -->
        <use_environment_credentials>1</use_environment_credentials>
        {{- end }}
        <region>{{ $s3.region }}</region>
        <metadata_path>/var/lib/clickhouse/disks/s3/</metadata_path>
        <!-- Skip the startup write-test: with keyless auth the pod only has creds
             once running as its IAM-bound SA, so a startup probe would crash-loop. -->
        <skip_access_check>1</skip_access_check>
      </s3>
      <s3_cache>
        <type>cache</type>
        <disk>s3</disk>
        <path>/var/lib/clickhouse/s3_cache/</path>
        <max_size>{{ .Values.clickhouse.s3CacheSize | int64 }}</max_size>
      </s3_cache>
    </disks>
    {{- end }}
    <policies>
      <tiered>
        <volumes>
          <!-- Hot volume MUST be named `default` so tables on the built-in `default`
               policy can switch to `tiered` (ClickHouse requires the new policy to
               contain a volume named `default`). -->
          <default>
            <disk>default</disk>
            <max_data_part_size_bytes>1073741824</max_data_part_size_bytes>
          </default>
          {{- if $s3.enabled }}
          <cold>
            <disk>s3_cache</disk>
          </cold>
          {{- end }}
        </volumes>
        {{- if $s3.enabled }}
        <move_factor>0.2</move_factor>
        {{- end }}
      </tiered>
    </policies>
  </storage_configuration>
</clickhouse>
{{- end -}}
