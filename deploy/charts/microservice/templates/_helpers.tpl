{{- define "microservice.name" -}}
{{- default .Release.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "microservice.labels" -}}
app.kubernetes.io/name: {{ include "microservice.name" . }}
app.kubernetes.io/part-of: orders-platform
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "microservice.selectorLabels" -}}
app.kubernetes.io/name: {{ include "microservice.name" . }}
{{- end -}}

{{- define "microservice.clientId" -}}
{{- $ids := .Values.global.workloadIdentityClientIds | default dict -}}
{{- .Values.serviceAccount.workloadIdentityClientId | default (get $ids (include "microservice.name" .)) -}}
{{- end -}}

{{- define "microservice.image" -}}
{{- $repo := .Values.image.repository | required "image.repository is required" -}}
{{- $tag := .Values.image.tag | required "image.tag is required" -}}
{{- if .Values.global.imageRegistry -}}
{{ .Values.global.imageRegistry }}/{{ $repo }}:{{ $tag }}
{{- else -}}
{{ $repo }}:{{ $tag }}
{{- end -}}
{{- end -}}
