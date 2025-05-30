image:
  repository: nvcr.io/nim/meta/llama3-8b-instruct
  tag: 1.0.0
imagePullSecrets:
  - name: registry-secret
model:
  name: meta/llama3-8b-instruct
  ngcAPISecret: ngc-api
persistence:
  enabled: true
statefulSet:
  enabled: false
resources:
  limits:
    nvidia.com/gpu: 1