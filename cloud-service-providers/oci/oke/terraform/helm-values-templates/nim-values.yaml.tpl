
imagePullSecrets:
- name: ${nvcr_secret}

model:
  ngcAPISecret: ${ngcapi_secret}

image:
  repository: ${nim_image_repository}
  tag: ${nim_image_tag}

resources:
  requests:
    nvidia.com/gpu: 1
  limits:
    nvidia.com/gpu: 1