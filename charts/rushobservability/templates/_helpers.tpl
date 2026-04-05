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
