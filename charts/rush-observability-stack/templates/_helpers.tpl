{{/* Stack-specific helpers. Core Rush helpers are provided by the dependency. */}}
{{- define "rush.stackQueryApiServiceName" -}}
{{- default (printf "%s-query-api" .Release.Name) .Values.global.rush.queryApi.serviceName | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rush.stackQueryApiUrl" -}}
{{- printf "http://%s:%v" (include "rush.stackQueryApiServiceName" .) .Values.global.rush.queryApi.port -}}
{{- end -}}

{{/* Existing ingest Secret, or the release-owned generated/value Secret. */}}
{{- define "rush.stackIngestApiKeySecretName" -}}
{{- if .Values.global.rush.ingestApiKeySecret.name -}}
{{- .Values.global.rush.ingestApiKeySecret.name -}}
{{- else if or .Values.global.rush.ingestApiKeySecret.autoGenerate .Values.global.rush.ingestApiKeySecret.value -}}
{{- printf "%s-ingest" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "rush.stackClickhouseService" -}}
{{- $ch := .Values.rush.clickhouse -}}
{{- if eq $ch.mode "standalone" -}}
{{- printf "%s-clickhouse" .Release.Name -}}
{{- else -}}
{{- $name := $ch.fullnameOverride | default "" -}}
{{- if not $name -}}
  {{- if contains "clickhouse" .Release.Name -}}
    {{- $name = .Release.Name -}}
  {{- else -}}
    {{- $name = printf "%s-clickhouse" .Release.Name -}}
  {{- end -}}
{{- end -}}
{{- printf "%s-service" $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "rush.stackClickhouseUrl" -}}
{{- if eq .Values.rush.clickhouse.mode "external" -}}
{{- required "rush.clickhouse.external.url is required in external mode" .Values.rush.clickhouse.external.url -}}
{{- else -}}
{{- printf "http://%s:8123" (include "rush.stackClickhouseService" .) -}}
{{- end -}}
{{- end -}}

{{- define "rush.stackClickhouseWriteEnv" -}}
- name: CLICKHOUSE_URL
  value: {{ include "rush.stackClickhouseUrl" . | quote }}
- name: CLICKHOUSE_USER
  valueFrom:
    secretKeyRef:
      name: {{ if eq .Values.rush.clickhouse.mode "external" }}{{ required "rush.clickhouse.external.credentialsSecret is required in external mode" .Values.rush.clickhouse.external.credentialsSecret }}{{ else }}rushobs-clickhouse-credentials{{ end }}
      key: {{ if eq .Values.rush.clickhouse.mode "external" }}{{ .Values.rush.clickhouse.external.userKey }}{{ else }}user{{ end }}
- name: CLICKHOUSE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ if eq .Values.rush.clickhouse.mode "external" }}{{ required "rush.clickhouse.external.credentialsSecret is required in external mode" .Values.rush.clickhouse.external.credentialsSecret }}{{ else }}rushobs-clickhouse-credentials{{ end }}
      key: {{ if eq .Values.rush.clickhouse.mode "external" }}{{ .Values.rush.clickhouse.external.passwordKey }}{{ else }}password{{ end }}
{{- end -}}

{{- define "rush.stackOtelEnabled" -}}
{{- if or (eq .Values.collectors.mode "otel") (eq .Values.collectors.mode "hybrid") }}true{{- end -}}
{{- end -}}

{{- define "rush.stackVectorEnabled" -}}
{{- if or (eq .Values.collectors.mode "vector") (eq .Values.collectors.mode "hybrid") }}true{{- end -}}
{{- end -}}

{{- define "rush.stackVectorFullOtel" -}}
{{- if and (eq .Values.collectors.mode "vector") (eq .Values.collectors.vector.mode "full-otel") }}true{{- end -}}
{{- end -}}
