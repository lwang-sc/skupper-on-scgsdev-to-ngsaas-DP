{{/*
# =============================================================================
# _helpers.tpl - Helm Template Helpers
# =============================================================================
#
# Shared helper functions for the Skupper Expose Services Cloud chart.
#
# =============================================================================
*/}}

{{/*
Sanitize envKey for use in Kubernetes resource names (RFC 1123 / DNS-1035).
Replaces underscores with hyphens to make it DNS-compatible.

Example: ns_dev__dev-dp6 → ns-dev--dev-dp6

Usage: {{ include "skupper.sanitizeEnvKey" "ns_dev__dev-dp6" }}
*/}}
{{- define "skupper.sanitizeEnvKey" -}}
{{- . | replace "_" "-" -}}
{{- end -}}

{{/*
Build MongoDB resource name from envKey and instance name.
Used for Listener name, host, and bridge service name.
Format: {sanitized-envKey}--{instance-name}
Example: ns-dev--dev-dp6--stellar-conf-mongo

Uses "--" (double hyphen) to separate envKey from instance name,
since both components can contain single hyphens.

Usage: {{ include "skupper.mongoResourceName" (dict "envKey" $envKey.key "instance" $instance.name) }}
*/}}
{{- define "skupper.mongoResourceName" -}}
{{- $sanitizedEnvKey := include "skupper.sanitizeEnvKey" .envKey -}}
{{- printf "%s--%s" $sanitizedEnvKey .instance -}}
{{- end -}}

{{/*
Build MongoDB routingKey from envKey and instance name.
Format: {sanitized-envKey}.{instance-name}
Example: ns-dev--dev-dp6.stellar-conf-mongo

NOTE: 
  - routingKey CAN contain dots - it's NOT a K8s resource name
  - envKey is still sanitized for consistency with DP cluster's Connector routingKey
  
This must match the Connector's routingKey on the DP cluster.

Usage: {{ include "skupper.mongoRoutingKey" (dict "envKey" $envKey.key "instance" $instance.name) }}
*/}}
{{- define "skupper.mongoRoutingKey" -}}
{{- $sanitizedEnvKey := include "skupper.sanitizeEnvKey" .envKey -}}
{{- printf "%s.%s" $sanitizedEnvKey .instance -}}
{{- end -}}

{{/*
Standard labels for all resources managed by this chart.

Usage: {{ include "skupper.commonLabels" . }}
*/}}
{{- define "skupper.commonLabels" -}}
app.kubernetes.io/name: skupper-expose-services-cloud
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}
