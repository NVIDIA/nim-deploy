{{/*
SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
SPDX-License-Identifier: LicenseRef-NvidiaProprietary

NVIDIA CORPORATION, its affiliates and licensors retain all intellectual
property and proprietary rights in and to this material, related
documentation and any modifications thereto. Any use, reproduction,
disclosure or distribution of this material and related documentation
without an express license agreement from NVIDIA CORPORATION or
its affiliates is strictly prohibited.
*/}}

{{/*
Copyright NVIDIA, Inc. All Rights Reserved.
SPDX-License-Identifier: APACHE-2.0
*/}}

{{/*
nim.common.v1.healthPort Provides options for chart authors' health ports (in case of separate health port)
*/}}
{{- define "nim.common.v1.healthPort" -}}
{{- if .Values.nim -}}
{{ coalesce .Values.nim.serverPort .Values.nim.httpPort }}
{{- end -}}
{{- end -}}

{{/*
Define the container ports for NIMs using either triton or all-OpenAI
*/}}
{{- define "nim.common.v1.ports" -}}
{{- if .Values.nim -}}
{{- if .Values.nim.httpPort }}
- containerPort: {{ .Values.nim.httpPort }}
  name: http
{{- end }}
{{- if .Values.nim.serverPort }}
- containerPort: {{ .Values.nim.serverPort }}
  name: http-server
{{- end }}
{{- if .Values.nim.grpcPort }}
- containerPort: {{ .Values.nim.grpcPort }}
  name: grpc
{{- end }}
{{- end -}}
{{- if .Values.metrics -}}
{{- if .Values.metrics.port }}
- containerPort: {{ .Values.metrics.port }}
  name: metrics
{{- end }}
{{- end -}}
{{- end -}}

{{/*
Define probes for single and multi-node templates
*/}}
{{- define "nim.common.v1.probes" -}}
{{- if .Values.livenessProbe.enabled }}
livenessProbe:
  httpGet:
    path: {{ .Values.livenessProbe.path }}
    port: {{ coalesce .Values.livenessProbe.port (include "nim.common.v1.healthPort" .) }}
  initialDelaySeconds: {{ .Values.livenessProbe.initialDelaySeconds | default 15 }}
  periodSeconds: {{ .Values.livenessProbe.periodSeconds | default 10 }}
  timeoutSeconds: {{ .Values.livenessProbe.timeoutSeconds | default 1 }}
  successThreshold: {{ .Values.livenessProbe.successThreshold | default 1 }}
  failureThreshold: {{ .Values.livenessProbe.failureThreshold | default 3 }}
{{- end }}
{{- if .Values.readinessProbe.enabled }}
readinessProbe:
  httpGet:
    path: {{ .Values.readinessProbe.path }}
    port: {{ coalesce .Values.readinessProbe.port (include "nim.common.v1.healthPort" .) }}
  initialDelaySeconds: {{ .Values.readinessProbe.initialDelaySeconds | default 15 }}
  periodSeconds: {{ .Values.readinessProbe.periodSeconds | default 10 }}
  timeoutSeconds: {{ .Values.readinessProbe.timeoutSeconds | default 1 }}
  successThreshold: {{ .Values.readinessProbe.successThreshold | default 1 }}
  failureThreshold: {{ .Values.readinessProbe.failureThreshold | default 3 }}
{{- end }}
{{- if .Values.startupProbe.enabled }}
startupProbe:
  httpGet:
    path: {{ .Values.startupProbe.path }}
    port: {{ coalesce .Values.startupProbe.port (include "nim.common.v1.healthPort" .) }}
  initialDelaySeconds: {{ .Values.startupProbe.initialDelaySeconds | default 40 }}
  periodSeconds: {{ .Values.startupProbe.periodSeconds | default 10 }}
  timeoutSeconds: {{ .Values.startupProbe.timeoutSeconds | default 1 }}
  successThreshold: {{ .Values.startupProbe.successThreshold | default 1 }}
  failureThreshold: {{ .Values.startupProbe.failureThreshold | default 180 }}
{{- end }}
{{- end -}}

{{/*
nim.common.v1.nimServerPort defines the primary HTTP port for the NIM
*/}}
{{- define "nim.common.v1.nimServerPort" -}}
{{- if .Values.nim -}}
{{ coalesce .Values.nim.serverPort .Values.nim.httpPort }}
{{- end -}}
{{- end -}}

{{/*
nim.common.v1.nimGrpcPort defines the primary GRPC port for the NIM
*/}}
{{- define "nim.common.v1.nimGrpcPort" -}}
{{- if .Values.nim -}}
{{- if and .Values.nim.grpcPort (ne .Values.nim.grpcPort 0) -}}
{{ .Values.nim.grpcPort }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
nim.common.v1.metricsPort defines the service metrics port name
*/}}
{{- define "nim.common.v1.metricsPort" -}}
{{- if (and .Values.service.metricsPort .Values.metrics.port ) -}}
"metrics"
{{- else if .Values.service.httpPort -}}
"http"
{{- else if .Values.service.serverPort -}}
"http-server"
{{- end -}}
{{- end -}}
