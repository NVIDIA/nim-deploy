{{/*
Expand the name of the chart.
*/}}
{{- define "nim-llm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "nim-llm.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "nim-llm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "nim-llm.labels" -}}
helm.sh/chart: {{ include "nim-llm.chart" . }}
{{ include "nim-llm.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "nim-llm.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nim-llm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "nim-llm.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "nim-llm.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create the pod template spec to run the NIM container
*/}}
{{- define "nim-llm.nim-pod-spec" -}}
{{- $pvcUsingTemplate := and .Values.persistence.enabled .Values.statefulSet.enabled (not .Values.persistence.existingClaim) (ne .Values.persistence.accessMode "ReadWriteMany")| ternary true false }}
template:
  metadata:
    {{- with .Values.podAnnotations }}
    annotations:
      {{- toYaml . | nindent 8 }}
    {{- end }}
    labels:
      {{- include "nim-llm.selectorLabels" . | nindent 8 }}
      {{- if .Values.model.labels }}
      {{- toYaml .Values.model.labels | nindent 8 }}
      {{- end }}
  spec:
    {{- if .Values.job.enabled }}
    restartPolicy: {{ .Values.job.restartPolicy }}
    {{- end }}
    {{- with .Values.imagePullSecrets }}
    imagePullSecrets:
      {{- toYaml . | nindent 8 }}
    {{- end }}
    serviceAccountName: {{ include "nim-llm.serviceAccountName" . }}
    securityContext:
      {{- toYaml .Values.podSecurityContext | nindent 8 }}
    initContainers:
    {{- with .Values.initContainers.ngcInit }}
      - name: ngc-model-puller
        image: "{{ .imageName  | default "eclipse/debian_jre" }}:{{ .imageTag | default "latest" }}"
        command: ["/bin/bash", "-c"]
        args: ["/scripts/ngc_pull.sh"]
        env:
          - name: NGC_CLI_API_KEY
            valueFrom:
              secretKeyRef:
                name: "{{ .secretName }}"
                key: NGC_CLI_API_KEY
          - name: NGC_DECRYPT_KEY
            valueFrom:
              secretKeyRef:
                name: "{{ .secretName }}"
                key: NGC_DECRYPT_KEY
                optional: true
          - name: STORE_MOUNT_PATH
            value: {{ .env.STORE_MOUNT_PATH | quote }}
          - name: NGC_CLI_ORG
            value: {{ .env.NGC_CLI_ORG | quote }}
          - name: NGC_CLI_TEAM
            value: {{ .env.NGC_CLI_TEAM | quote }}
          - name: NGC_CLI_VERSION
            value: {{ .env.NGC_CLI_VERSION | quote }}
          - name: NGC_MODEL_NAME
            value: {{ .env.NGC_MODEL_NAME | quote }}
          - name: NGC_MODEL_VERSION
            value: {{ .env.NGC_MODEL_VERSION | quote }}
          - name: MODEL_NAME
            value: {{ .env.MODEL_NAME | quote }}
          - name: TARFILE
            value: {{ .env.TARFILE | quote }}
          - name: NGC_EXE
            value: {{ .env.NGC_EXE | default "ngc" | quote }}
          - name: DOWNLOAD_NGC_CLI
            value: {{ .env.DOWNLOAD_NGC_CLI | default "false" | quote }}
        volumeMounts:
          - mountPath: /scripts
            name: scripts-volume
          - mountPath: /model-store
            name: model-store
            {{- if .Values.csi.enabled }}
            readOnly: {{ .Values.csi.readOnly }}
            {{- end }}
    {{- end }}
    {{- range .Values.initContainers.extraInit }}
      - {{ . | toYaml | nindent 10 }}
    {{- end }}
    containers:
      - name: {{ .Chart.Name }}
        securityContext:
          {{- toYaml .Values.containerSecurityContext | nindent 12 }}
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        {{- if or .Values.customCommand .Values.model.legacyCompat }}
        command:
          {{- if .Values.customCommand }}
          {{- range .Values.customCommand }}
           - {{ . }}
          {{- end }}
          {{- else }}
          - nemollm_inference_ms
          - --model_name
          - {{ .Values.model.name | quote }}
          - --num_gpus
          - {{ .Values.model.numGpus | quote }}
          {{- if .Values.model.nemo_port }}
          - --nemo_port
          - {{ .Values.model.nemo_port | quote }}
          {{- end }}
          {{- if or .Values.model.openai_port .Values.model.openai_port }}
          - --openai_port
          - {{ .Values.model.openaiPort | default .Values.model.openai_port | quote }}
          {{- end }}
          {{- if .Values.model.openai_host }}
          - --host
          - {{ .Values.model.openai_host | quote }}
          {{- end }}
          {{- if .Values.healthPort }}
          - --health_port
          - {{ .Values.healthPort | quote }}
          {{- end }}
          {{- if .Values.model.numWorkers }}
          - --num_workers
          - {{ .Values.model.numWorkers | quote }}
          {{- end }}
          {{- if .Values.model.logLevel }}
          - --log_level
          - {{ .Values.model.logLevel | quote }}
          {{- end }}
          {{- if .Values.model.tritonURL }}
          - --triton_url
          - {{ .Values.model.tritonURL | quote }}
          {{- end }}
          {{- if .Values.model.tritonModelName }}
          - --triton_model_name
          - {{ .Values.model.tritonModelName | quote }}
          {{- end }}
          {{- if .Values.model.trtModelName }}
          - --trt_model_name
          - {{ .Values.model.trtModelName | quote }}
          {{- end }}
          {{- if .Values.model.customizationSource }}
          - --customization_sourcemodel-cache
          - {{ .Values.model.customizationSource | quote }}
          {{- end }}
          {{- if .Values.model.dataStoreURL }}
          - --data_store_url
          - {{ .Values.model.dataStoreURL | quote }}
          {{- end }}
          {{- if .Values.model.modelStorePath }}
          - --model_store_path
          - {{ .Values.model.modelStorePath | quote }}
          {{- end }}
          {{- end }}
        {{- end }}
        env:
          - name: NIM_CACHE_PATH
            value: {{ .Values.model.nimCache | quote }}
          - name: NGC_API_KEY
            valueFrom:
              secretKeyRef:
                name: {{ .Values.model.ngcAPISecret }}
                key: NGC_CLI_API_KEY
          - name: NIM_SERVER_PORT
            value: {{ .Values.model.openaiPort | quote }}
          - name: NIM_JSONL_LOGGING
            value: {{ ternary "1" "0" .Values.model.jsonLogging | quote }}
          - name: NIM_LOG_LEVEL
            value: {{ .Values.model.logLevel | quote }}
          {{- if .Values.env }}
          {{- toYaml .Values.env | nindent 12 }}
          {{- end }}
        ports:
          {{- if .Values.model.legacyCompat }}
          - containerPort: 8000
            name: http
          {{- end }}
          {{- if and .Values.healthPort .Values.model.legacyCompat }}
          - containerPort: {{ .Values.healthPort }}
            name: health
          {{- end }}
          {{- if .Values.service.grpc_port }}
          - containerPort: 8001
            name: grpc
          {{- end }}
          {{- if and .Values.metrics.enabled .Values.model.legacyCompat }}
          - containerPort: 8002
            name: metrics
          {{- end }}
          {{- if or .Values.model.openaiPort .Values.model.openai_port }}
          - containerPort: {{ .Values.model.openaiPort | default .Values.model.openai_port }}
            name: http-openai
          {{- end }}
          {{- if or .Values.model.nemoPort .Values.model.nemo_port }}
          - containerPort: {{ .Values.model.nemoPort | default .Values.model.nemo_port }}
            name: http-nemo
          {{- end }}
        {{- if .Values.livenessProbe.enabled }}
        {{- with .Values.livenessProbe }}
        livenessProbe:
          {{- if eq .method "http" }}
          httpGet:
            path: {{ .path }}
            port: {{ $.Values.model.legacyCompat | ternary "health" "http-openai" }}
          {{- else if eq .method "script" }}
          exec:
            command:
            {{- toYaml .command | nindent 16 }}
          {{- end }}
          initialDelaySeconds: {{ .initialDelaySeconds }}
          periodSeconds: {{ .periodSeconds }}
          timeoutSeconds: {{ .timeoutSeconds }}
          successThreshold: {{ .successThreshold }}
          failureThreshold: {{ .failureThreshold }}
        {{- end }}
        {{- end }}
        {{- if .Values.readinessProbe.enabled }}
        {{- with .Values.readinessProbe }}
        readinessProbe:
          httpGet:
            path: {{ .path }}
            port: {{ $.Values.model.legacyCompat | ternary "health" "http-openai" }}
          initialDelaySeconds: {{ .initialDelaySeconds }}
          periodSeconds: {{ .periodSeconds }}
          timeoutSeconds: {{ .timeoutSeconds }}
          successThreshold: {{ .successThreshold }}
          failureThreshold: {{ .failureThreshold }}
        {{- end }}
        {{- end }}
        {{- if .Values.startupProbe.enabled }}
        {{- with .Values.startupProbe }}
        startupProbe:
          httpGet:
            path: {{ .path }}
            port: {{ $.Values.model.legacyCompat | ternary "health" "http-openai" }}
          initialDelaySeconds: {{ .initialDelaySeconds }}
          periodSeconds: {{ .periodSeconds }}
          timeoutSeconds: {{ .timeoutSeconds }}
          successThreshold: {{ .successThreshold }}
          failureThreshold: {{ .failureThreshold }}
        {{- end }}
        {{- end }}
        resources:
          {{- toYaml .Values.resources | nindent 12 }}
        volumeMounts:
          - name: model-store
            {{- if .Values.model.legacyCompat }}
            mountPath: {{ .Values.model.nimCache }}
            subPath: {{ .Values.model.subPath }}
            {{- else }}
            mountPath: {{ .Values.model.nimCache }}
            {{- end }}
            {{- if .Values.csi.enabled }}
            readOnly: {{ .Values.csi.readOnly }}
            {{- end }}
          - mountPath: /dev/shm
            name: dshm
          - name: scripts-volume 
            mountPath: /scripts
        {{- if .Values.extraVolumeMounts }}
        {{- range $k, $v := .Values.extraVolumeMounts }}
          - name: {{ $k }}
            {{- toYaml $v | nindent 12 }}
        {{- end }}
        {{- end }}
    terminationGracePeriodSeconds: 60
    {{- with .Values.nodeSelector }}
    nodeSelector:
      {{- toYaml . | nindent 8 }}
    {{- end }}
    {{- with .Values.affinity }}
    affinity:
      {{- toYaml . | nindent 8 }}
    {{- end }}
    {{- with .Values.tolerations }}
    tolerations:
      {{- toYaml . | nindent 8 }}
    {{- end }}
    volumes:
      - name: dshm
        emptyDir:
          medium: Memory
      - name: scripts-volume
        configMap:
          name: {{ .Release.Name }}-scripts-configmap
          defaultMode: 0555
      {{- if not $pvcUsingTemplate }}
      - name: model-store
        {{- if .Values.persistence.enabled }}
        persistentVolumeClaim:
          claimName:  {{ .Values.persistence.existingClaim | default (include "nim-llm.fullname" .) }}
        {{- else if .Values.hostPath.enabled }}
        hostPath:
          path: {{ .Values.hostPath.path }}
          type: DirectoryOrCreate
        {{- else if .Values.nfs.enabled }}
        nfs:
          server: {{ .Values.nfs.server | quote }}
          path: {{ .Values.nfs.path }}
          readOnly: {{ .Values.nfs.readOnly }}
        {{- else if .Values.csi.enabled }}
        csi:
          driver: {{ .Values.csi.driver }}
          readOnly: {{ .Values.csi.readOnly }}
          volumeAttributes:
            {{- toYaml .Values.csi.volumeAttributes | nindent 12 }}
        {{- else }}
        emptyDir: {}
        {{- end }}
      {{- end }}
    {{- if .Values.extraVolumes }}
    {{- range $k, $v := .Values.extraVolumes }}
      - name: {{ $k }}
        {{- toYaml $v | nindent 8 }}
    {{- end }}
    {{- end }}
{{- end }}