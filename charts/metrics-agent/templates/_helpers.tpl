{{- define "metrics-agent.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "metrics-agent.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "metrics-agent.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "metrics-agent.labels" -}}
helm.sh/chart: {{ include "metrics-agent.chart" . }}
{{ include "metrics-agent.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}

{{- define "metrics-agent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "metrics-agent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: metrics-agent
{{- end }}

{{- define "metrics-agent.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "metrics-agent.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- required "serviceAccount.name is required when serviceAccount.create=false" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "metrics-agent.imageRepository" -}}
{{- $source := required "image.repository is required" .Values.image.repository -}}
{{- $registry := default "" .Values.global.image.registry -}}
{{- if and $registry (not (regexMatch "^[A-Za-z0-9][A-Za-z0-9._-]*(:[0-9]+)?(/[A-Za-z0-9][A-Za-z0-9._-]*)*/?$" $registry)) -}}
{{- fail "global.image.registry must be a registry host with an optional port or path, without a URL scheme" -}}
{{- end -}}
{{- $registry = trimSuffix "/" $registry -}}
{{- if $registry -}}
{{- $parts := splitList "/" $source -}}
{{- $first := first $parts -}}
{{- $repository := $source -}}
{{- if and (gt (len $parts) 1) (or (contains "." $first) (contains ":" $first) (eq $first "localhost")) -}}
{{- $repository = join "/" (rest $parts) -}}
{{- end -}}
{{- printf "%s/%s" $registry $repository -}}
{{- else -}}
{{- $source -}}
{{- end -}}
{{- end -}}

{{- define "metrics-agent.image" -}}
{{- $repository := include "metrics-agent.imageRepository" . -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" $repository .Values.image.digest }}
{{- else -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag -}}
{{- printf "%s:%s" $repository $tag }}
{{- end }}
{{- end }}

{{- define "metrics-agent.httpPort" -}}
{{- if .Values.ui.enabled -}}
{{- default .Values.service.port .Values.ui.port -}}
{{- else -}}
{{- .Values.service.port -}}
{{- end -}}
{{- end -}}

{{- define "metrics-agent.rushRemoteWriteUrl" -}}
{{- if .Values.rushRemoteWrite.url -}}
{{- .Values.rushRemoteWrite.url -}}
{{- else if .Values.global.rush.stack.enabled -}}
{{- $service := default (printf "%s-query-api" .Release.Name) .Values.global.rush.queryApi.serviceName -}}
{{- printf "http://%s:%v/prom/api/v1/write" $service .Values.global.rush.queryApi.port -}}
{{- end -}}
{{- end -}}

{{- define "metrics-agent.rushRemoteWriteSecretName" -}}
{{- if .Values.rushRemoteWrite.bearerTokenSecret.name -}}
{{- .Values.rushRemoteWrite.bearerTokenSecret.name -}}
{{- else if .Values.global.rush.ingestApiKeySecret.name -}}
{{- .Values.global.rush.ingestApiKeySecret.name -}}
{{- else if or .Values.global.rush.ingestApiKeySecret.autoGenerate .Values.global.rush.ingestApiKeySecret.value -}}
{{- printf "%s-ingest" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "metrics-agent.rushRemoteWriteSecretKey" -}}
{{- if .Values.rushRemoteWrite.bearerTokenSecret.name -}}
{{- .Values.rushRemoteWrite.bearerTokenSecret.key -}}
{{- else -}}
{{- .Values.global.rush.ingestApiKeySecret.key -}}
{{- end -}}
{{- end -}}
