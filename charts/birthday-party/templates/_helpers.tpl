{{/* The origin guests open: publicUrl, or one derived from the Ingress host. */}}
{{- define "birthday-party.publicUrl" -}}
{{- if .Values.publicUrl -}}
{{- .Values.publicUrl -}}
{{- else if .Values.ingress.enable -}}
{{- printf "%s://%s" (ternary "https" "http" .Values.ingress.tls) (required "ingress.host is required when ingress.enable is true" .Values.ingress.host) -}}
{{- else -}}
http://localhost:3000
{{- end -}}
{{- end -}}
