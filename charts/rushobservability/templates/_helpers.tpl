{{- define "rush.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rush.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/*
ClickHouse service DNS name inside the cluster. The Altinity subchart
creates a service named `clickhouse-{release}-clickhouse`.
*/}}
{{- define "rush.clickhouseService" -}}
clickhouse-{{ .Release.Name }}-clickhouse
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

{{/*
Whether the OpenTelemetry Collector should be deployed, based on the
selected collectors.mode.
*/}}
{{- define "rush.otelEnabled" -}}
{{- $m := .Values.collectors.mode -}}
{{- if or (eq $m "otel") (eq $m "hybrid") -}}true{{- end -}}
{{- end -}}

{{/*
Whether Vector should be deployed, based on collectors.mode.
*/}}
{{- define "rush.vectorEnabled" -}}
{{- $m := .Values.collectors.mode -}}
{{- if or (eq $m "vector") (eq $m "hybrid") -}}true{{- end -}}
{{- end -}}

{{/*
Whether Vector is running in "full-otel" sub-mode (accepts OTLP + tails
logs). Only meaningful when collectors.mode = "vector".
*/}}
{{- define "rush.vectorFullOtel" -}}
{{- if and (eq .Values.collectors.mode "vector") (eq .Values.collectors.vector.mode "full-otel") -}}true{{- end -}}
{{- end -}}
