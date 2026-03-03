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

{{- define "nim.common.v1.configmap" -}}
{{- $hasScript := .Files.Glob "files/script.sh" }}
{{- $hasConfig := .Files.Glob "files/config.yaml" }}

{{- if $hasScript }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-script
  labels:
    {{- include "nim.common.v1.labels" . | nindent 4 }}
data:
  script.sh: |-
{{ .Files.Get "files/script.sh" | indent 4 }}
{{- end }}

{{- if $hasConfig }}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-config
  labels:
    {{- include "nim.common.v1.labels" . | nindent 4 }}
data:
  config.yaml: |-
{{ .Files.Get "files/config.yaml" | indent 4 }}
{{- end }}

{{- end -}}