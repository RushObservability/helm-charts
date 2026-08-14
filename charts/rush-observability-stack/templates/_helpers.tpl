{{/* Stack-specific helpers. Core Rush helpers are provided by the dependency. */}}
{{- define "rush.stackQueryApiServiceName" -}}
{{- default (printf "%s-query-api" .Release.Name) .Values.global.rush.queryApi.serviceName | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "rush.stackQueryApiUrl" -}}
{{- printf "http://%s:%v" (include "rush.stackQueryApiServiceName" .) .Values.global.rush.queryApi.port -}}
{{- end -}}

{{- define "rush.stackClickhouseService" -}}
{{- $ch := .Values.rushobservability.clickhouse -}}
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
{{- if eq .Values.rushobservability.clickhouse.mode "external" -}}
{{- required "rushobservability.clickhouse.external.url is required in external mode" .Values.rushobservability.clickhouse.external.url -}}
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
      name: {{ if eq .Values.rushobservability.clickhouse.mode "external" }}{{ required "rushobservability.clickhouse.external.credentialsSecret is required in external mode" .Values.rushobservability.clickhouse.external.credentialsSecret }}{{ else }}rushobs-clickhouse-credentials{{ end }}
      key: {{ if eq .Values.rushobservability.clickhouse.mode "external" }}{{ .Values.rushobservability.clickhouse.external.userKey }}{{ else }}user{{ end }}
- name: CLICKHOUSE_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ if eq .Values.rushobservability.clickhouse.mode "external" }}{{ required "rushobservability.clickhouse.external.credentialsSecret is required in external mode" .Values.rushobservability.clickhouse.external.credentialsSecret }}{{ else }}rushobs-clickhouse-credentials{{ end }}
      key: {{ if eq .Values.rushobservability.clickhouse.mode "external" }}{{ .Values.rushobservability.clickhouse.external.passwordKey }}{{ else }}password{{ end }}
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
