# Deploy NVIDIA NIM microservices on RunAI

This document describes the procedure for deploying NIM Microservice employing helm on a RunAI cluster.

## Prerequisites
1.  Kubernetes cluster
2.  RunAI Installed (version \>= 2.18)
3.  GPU Operator
4.  Further NIM Prerequisites can be found here
    ([[https://developer.nvidia.com/docs/nemo-microservices/inference/getting_started/deploy-helm.html]{.underline}](https://developer.nvidia.com/docs/nemo-microservices/inference/getting_started/deploy-helm.html))
5.  Helm installed locally

## Integration features

| Feature                            | Exists             |
|------------------------------------|--------------------|
| Deploy through helm CLI            | :white_check_mark: | 
| Engine capabilities (Scheduling)   | :white_check_mark: |  
| Visibility (UI + CLI)              | :white_check_mark: |
| Submit through RunAI Workload API  |                    | 
| Submit through RunAI UI            |                    |   

## Preparation (Single time)

1.  RunAI
    a.  Create a project to deploy the NIM within (Can be existing
        project)

        i.  For example: team-a

    b.  Enforce RunAI Scheduler in the project's namespace

        i.  Kubectl annotate ns runai-team-a
            runai/enforce-scheduler-name=true

        ii. [[https://docs.run.ai/v2.18/admin/runai-setup/config/default-scheduler/]{.underline}](https://docs.run.ai/v2.18/admin/runai-setup/config/default-scheduler/)

2.  NVIDIA NGC

   a.  Create API Key
      Please follow the guidance in the NVIDIA NIM [Getting Started]([https://docs.nvidia.com/nim/large-language-models/latest/getting-started.html#option-2-from-ngc](https://docs.nvidia.com/nim/large-language-models/latest/getting-started.html#id1)) to generate a properly scoped API key if you haven't already.  For illustration purposes the generated key will be incidated as `XXXYYYZZZ` below.

  b.  Add NIM Helm repository to deploy NIM charts:
  
  `helm repo add nemo-ms "https://helm.ngc.nvidia.com/ohlfw0olaadg/ea-participants" --username=\$oauthtoken --password=XXXYYYZZZ`

  c.  Create docker registry secret to pull NIM images:
  
  `kubectl create secret docker-registry -n runai-team-a registry-secret --docker-username=\$oauthtoken --docker-password=XXXYYYZZZ`

  d.  Create docker secret to pull models:
  
  `kubectl create secret generic ngc-api -n runai-team-a --from-literal=NGC_CLI_API_KEY=XXXYYYZZZ`


## Deployment (Any time you want to deploy NIM)

Prepare the values file (changing as needed) values.yaml
```
initContainers:
  ngcInit:
    imageName: nvcr.io/ohlfw0olaadg/ea-participants/nim_llm
    imageTag: 24.06
    secretName: ngc-api
    env:
      STORE_MOUNT_PATH: /model-store
      NGC_CLI_ORG: ohlfw0olaadg
      NGC_CLI_TEAM: ea-participants
      NGC_MODEL_NAME: llama2-13b-chat
      NGC_MODEL_VERSION: a100x2_fp16_24.06
      NGC_EXE: ngc
      DOWNLOAD_NGC_CLI: "true"
      NGC_CLI_VERSION: "3.34.1"
      MODEL_NAME: llama2-13b-chat

image:
  repository: nvcr.io/ohlfw0olaadg/ea-participants/nim_llm
  tag: 24.06

imagePullSecrets:
  - name: registry-secret

model:
  numGpus: 2
  name: llama2-13b-chat
  openai_port: 9999
```

Run the following command:
```
helm -n runai-team-a install llama2-13b-chat-nim nemo-ms/nemollm-inference -f values.yaml
```
# Note
-   The namespace we deploy the helm chart is the RunAI Project namespace (runai-team-a)
-   For different models consult the NVIDIA documentation
    [[https://developer.nvidia.com/docs/nemo-microservices/inference/getting_started/deploy-helm.html]{.underline}](https://developer.nvidia.com/docs/nemo-microservices/inference/getting_started/deploy-helm.html)

View the model within the RunAI UI:

![](media/image1.png){width="6.5in" height="2.5833333333333335in"}
