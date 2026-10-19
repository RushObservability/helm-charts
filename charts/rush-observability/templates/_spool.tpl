{{/* Shared spec for retained spool PVCs and StatefulSet claim templates. */}}
{{- define "rush.queryApiHeadlessServiceName" -}}
{{- printf "%s-query-api-headless" (include "rush.fullname" . | trunc 44 | trimSuffix "-") -}}
{{- end -}}

{{- define "rush.spoolClaimSpec" -}}
accessModes:
  {{- toYaml .accessModes | nindent 2 }}
{{- if eq .storageClass "-" }}
storageClassName: ""
{{- else if .storageClass }}
storageClassName: {{ .storageClass | quote }}
{{- end }}
resources:
  requests:
    storage: {{ .size | quote }}
{{- end -}}

{{/* Run as the app user: fsGroup permits mkdir but not chmod of a root-owned PV.
Move legacy flat outboxes within the same filesystem before the sole writer starts.
Query API images may be distroless, so use a dedicated, digest-pinned helper. */}}
{{- define "rush.spoolInitContainers" -}}
{{- $spools := list (dict "name" "audit-spool" "path" "/var/lib/rush/audit-spool" "directory" "outbox" "extension" "json") -}}
{{- if eq .Values.queryApi.config.ingest.buffer.backend "disk" -}}
{{- $spools = append $spools (dict "name" "rush-spool" "path" "/var/lib/rush/spool" "directory" "queue" "extension" "spool") -}}
{{- end -}}
{{- range $spool := $spools }}
- name: prepare-{{ $spool.name }}
  image: {{ include "rush.image" (dict "root" $ "image" $.Values.queryApi.spoolInit.image) | quote }}
  imagePullPolicy: {{ $.Values.queryApi.spoolInit.image.pullPolicy }}
  command: ["/bin/sh", "-ec"]
  args:
    - |
      root={{ $spool.path }}
      target="$root/{{ $spool.directory }}"
      if [ -L "$target" ]; then
        echo "spool directory must not be a symlink" >&2
        exit 1
      fi
      mkdir -p "$target"
      chmod 700 "$target"
      for source in "$root"/*.{{ $spool.extension }}; do
        [ -e "$source" ] || [ -L "$source" ] || continue
        destination="$target/${source##*/}"
        if [ ! -f "$source" ] || [ -L "$source" ] || [ -e "$destination" ] || [ -L "$destination" ]; then
          echo "spool migration needs operator review: invalid entry or duplicate filename" >&2
          exit 1
        fi
        mv "$source" "$destination"
      done
      sync
  securityContext:
    runAsUser: 999
    runAsGroup: 999
    {{- include "rush.hardenedContainerSecurityContext" $ | nindent 4 }}
  resources:
    {{- toYaml $.Values.queryApi.spoolInit.resources | nindent 4 }}
  volumeMounts:
    - name: {{ $spool.name }}
      mountPath: {{ $spool.path }}
{{- end }}
{{- end -}}
