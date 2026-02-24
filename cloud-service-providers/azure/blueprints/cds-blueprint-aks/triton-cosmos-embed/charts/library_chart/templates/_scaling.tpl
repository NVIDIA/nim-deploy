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

{{- define "nim.common.v1.hpa" -}}
---
{{ if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "nim.common.v1.fullname" . }}
  labels:
    {{- include "nim.common.v1.labels" . | nindent 4 }}
spec:
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  scaleTargetRef:
    {{- if (and .Values.multinode (and .Values.multiNode.enabled | default false (or (.Capabilities.APIVersions.Has "leaderworkerset.x-k8s.io/v1") .Values.multiNode.leaderWorkerSet.enabled))) }}
    apiVersion: leaderworkerset.x-k8s.io/v1
    kind: LeaderWorkerSet
    {{- else if (and .Values.statefulSet (.Values.statefulSet.enabled | default false)) }}
    apiVersion: apps/v1
    kind: StatefulSet
    {{- else }}
    apiVersion: apps/v1
    kind: Deployment
    {{- end }}
    name: {{ include "nim.common.v1.fullname" . }}
  metrics:
    {{- range .Values.autoscaling.metrics }}
        - {{- . | toYaml | nindent 10 }}
    {{- end }}
  {{- if .Values.autoscaling.scaleDownStabilizationSecs }}
  behavior:
    scaleDown:
      stabilizationWindowSeconds: {{ .Values.autoscaling.scaleDownStabilizationSecs }}
  {{- end }}
{{ end }}

{{- end -}}
