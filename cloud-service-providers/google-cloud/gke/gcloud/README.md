# Deploy NVIDIA NIM on Google Kubernetes Engine

## Introduction
This tutorial will guide you through deploying a [nvcr.io/nim/meta/llama3-8b-instruct](https://catalog.ngc.nvidia.com/orgs/nvidia/teams/aiworkflows/helm-charts/rag-app-text-chatbot-langchain) on Google Kubernetes Engine (GKE). You'll leverage the power of NVIDIA Inference Microservices (NIMs) to easily deploy AI models.

## Prerequisites
- **GCloud SDK:** Ensure you have the Google Cloud SDK installed and configured.
- **Project:**  A Google Cloud project with billing enabled.
- **Permissions:**  Sufficient permissions to create GKE clusters and other related resources.
- **kubectl:** kubectl command-line tool installed and configured.
- **NVIDIA API key:** required to download NIMs: [NGC API key](https://org.ngc.nvidia.com/setup/api-key). 
- **NVIDIA GPUs:** One of the below GPUs should work
  - [NVIDIA L4 GPU (1)](https://cloud.google.com/compute/docs/gpus#l4-gpus)
  - [NVIDIA A100 40GB GPU (1)](https://cloud.google.com/compute/docs/gpus#a100-gpus)
  - [NVIDIA H100 80GB GPU (1)](https://cloud.google.com/compute/docs/gpus#a3-series)

## Task 1. Infrastructure Deployment
1. Open __Cloud Shell__ or your terminal.

2. Specify the following parameters
    ```bash
    export PROJECT_ID=<YOUR PROJECT ID>
    export REGION=<YOUR REGION>
    export ZONE=<YOUR ZONE>
    export CLUSTER_NAME=nim-demo
    export NODE_POOL_MACHINE_TYPE=g2-standard-16	
    export CLUSTER_MACHINE_TYPE=e2-standard-4
    export GPU_TYPE=nvidia-l4
    export GPU_COUNT=1
    ```

3. Create GKE Cluster
    ```
    gcloud container clusters create ${CLUSTER_NAME} \
        --project=${PROJECT_ID} \
        --location=${ZONE} \
        --release-channel=rapid \
        --machine-type=${CLUSTER_MACHINE_TYPE} \
        --num-nodes=1
    ```

4. Create GPU node pool
    ```
    gcloud container node-pools create gpupool \
        --accelerator type=${GPU_TYPE},count=${GPU_COUNT},gpu-driver-version=latest \
        --project=${PROJECT_ID} \
        --location=${ZONE} \
        --cluster=${CLUSTER_NAME} \
        --machine-type=${NODE_POOL_MACHINE_TYPE} \
        --num-nodes=1
    ```

## Task 2. Configure NVIDIA NGC API Key

```
export NGC_CLI_API_KEY="<YOUR NGC API KEY>"
```

## Task 3. Deploying NVIDIA NIM

1. Fetch NIM LLM Helm Chart:
    ```
    helm fetch https://helm.ngc.nvidia.com/nim/charts/nim-llm-1.3.0.tgz --username='$oauthtoken' --password=$NGC_CLI_API_KEY
    ```

2. Create a NIM Namespace:
    ```
    kubectl create namespace nim
    ```

3. Configure secrets:
    ```
    kubectl create secret docker-registry registry-secret --docker-server=nvcr.io --docker-username='$oauthtoken'     --docker-password=$NGC_CLI_API_KEY -n nim
    
    kubectl create secret generic ngc-api --from-literal=NGC_API_KEY=$NGC_CLI_API_KEY -n nim
    ```

4. Setup NIM Configuration:
    ```
    cat <<EOF > nim_custom_value.yaml
    image:
      repository: "nvcr.io/nim/meta/llama3-8b-instruct" # container location
      tag: 1.0.0 # NIM version you want to deploy
    model:
      ngcAPISecret: ngc-api  # name of a secret in the cluster that includes a key named NGC_CLI_API_KEY and is an NGC API key
    persistence:
      enabled: true
    imagePullSecrets:
      - name: registry-secret # name of a secret used to pull nvcr.io images, see https://kubernetes.io/docs/tasks/    configure-pod-container/pull-image-private-registry/
    EOF
    ```

5. Launching NIM deployment:
    ```
    helm install my-nim nim-llm-1.1.2.tgz -f nim_custom_value.yaml --namespace nim
    ```

    Verify NIM pod is running
    ```
    kubectl get pods -n nim
    ```

6. Testing NIM deployment
    Once we’ve verified that our NIM service was deployed successfully. We can make inference requests to see what type of feedback we’ll receive from the NIM service. In order to do this, we enable port forwarding on the service to be able to access the NIM from our localhost on port 8000:
    ```
    kubectl port-forward service/my-nim-nim-llm 8000:8000 -n nim
    ```
    Next, we can open another terminal or tab in the cloud shell and try the following request:
    ```
    curl -X 'POST' \
      'http://localhost:8000/v1/chat/completions' \
      -H 'accept: application/json' \
      -H 'Content-Type: application/json' \
      -d '{
      "messages": [
        {
          "content": "You are a polite and respectful chatbot helping people plan a vacation.",
          "role": "system"
        },
        {
          "content": "What should I do for a 4 day vacation in Spain?",
          "role": "user"
        }
      ],
      "model": "meta/llama3-8b-instruct",
      "max_tokens": 128,
      "top_p": 1,
      "n": 1,
      "stream": false,
      "stop": "\n",
      "frequency_penalty": 0.0
    }'
    ```
    If you get a chat completion from the NIM service, that means the service is working as expected! 

## Task 4. Cleanup

```bash
gcloud container clusters delete $CLUSTER_NAME --zone=$ZONE
```

### Learn More

Be sure to check out the following articles for more information:
* [Google Kubernetes Engine (GKE)](https://cloud.google.com/kubernetes-engine/docs/concepts/choose-cluster-mode#why-standard)
* [NVIDIA GPUs](https://cloud.google.com/compute/docs/gpus)
* [NVIDIA AI Enterprise](https://console.cloud.google.com/marketplace/product/nvidia/nvidia-ai-enterprise-vmi)
* [NVIDIA NIMs](https://www.nvidia.com/en-us/ai/)
