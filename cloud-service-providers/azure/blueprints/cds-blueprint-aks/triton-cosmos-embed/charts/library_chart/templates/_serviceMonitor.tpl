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
nim.common.v1.serviceMonitor creates a ServiceMonitor object where supported and desired
*/}}
{{- define "nim.common.v1.serviceMonitor" -}}
---
{{- if .Values.metrics.serviceMonitor.enabled -}}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ include "nim.common.v1.fullname" . }}
  labels:
    {{- include "nim.common.v1.labels" . | nindent 4 }}
    {{- if .Values.metrics.serviceMonitor.additionalLabels }}
    {{- toYaml .Values.metrics.serviceMonitor.additionalLabels | nindent 4 }}
    {{- end }}
spec:
  selector:
    matchLabels:
      {{- include "nim.common.v1.selectorLabels" . | nindent 6 }}
  endpoints:
  - port: {{ include "nim.common.v1.metricsPort" . }}

{{- end -}}
{{- end -}}
