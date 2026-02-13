# Deploy NVIDIA VSS Blueprint with Helm on Google Compute Engine

## Introduction
This tutorial will guide you through deploying a full [Video Search and Summarization Blueprint](https://build.nvidia.com/nvidia/video-search-and-summarization) (v2.4.1).

Insightful, accurate, and interactive video analytics AI agents enable a range of industries to make better decisions faster. These AI agents are given tasks through natural language and can perform complex operations like video summarization and visual question-answering, unlocking entirely new application possibilities. The NVIDIA AI Blueprint makes it easy to get started building and customizing video analytics AI agents for video search and summarization — all powered by generative AI, vision language models (VLMs) like Cosmos Nemotron VLMs, large language models (LLMs) like Llama Nemotron LLMs, NVIDIA NeMo Retriever, and NVIDIA NIM.
This guide comes from the [Fully Local Single GPU Deployment](https://docs.nvidia.com/vss/latest/content/vss_dep_helm.html#fully-local-single-gpu-deployment) using Helm.

## Prerequisites
- **Gcloud SDK:** Ensure you have the Google Cloud SDK installed and configured.
- **Project:**  A Google Cloud project with billing enabled.
- **Permissions:**  Sufficient permissions to create a GCP VM and other related resources (VPC, firewall rules).
- **NVIDIA API key:** required to download NIMs: [NGC API key](https://org.ngc.nvidia.com/setup/api-key).
- **HuggingFace Token**: required to fetch CosmosReason2 NIM. [Make sure to accept terms here](https://huggingface.co/nvidia/Cosmos-Reason2-8B). 
- **NVIDIA GPUs:** We are using just one GCP G4 instance with an RTX PRO 6000 for this project.
  - [NVIDIA RTX PRO 6000 Blackwell Server Edition)](https://docs.cloud.google.com/compute/docs/gpus#rtx-6000-gpus)

## Software Components
Below is the architecture of the VSS Blueprint, leveraging several NIMs:
<div align="center">
  <img src="https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization/raw/main/deploy/images/vss_architecture.png" width="800">
</div>

1. **NIM microservices**: Here are the models used in this blueprint:

    - [Cosmos-Reason2-8B](https://build.nvidia.com/nvidia/cosmos-reason2-8b)
    - [meta / llama-3.1-8b-instruct](https://build.nvidia.com/meta/llama-3_1-8b-instruct)
    - [llama-3_2-nv-embedqa-1b-v2](https://build.nvidia.com/nvidia/llama-3_2-nv-embedqa-1b-v2)
    - [llama-3_2-nv-rerankqa-1b-v2](https://build.nvidia.com/nvidia/llama-3_2-nv-rerankqa-1b-v2)

## Task 1. Infrastructure Deployment
1. Open __Cloud Shell__ or your terminal.

2. Specify the following parameters
    ```bash
    export PROJECT_ID=<YOUR PROJECT ID>
    export REGION=<YOUR REGION>
    export ZONE=<YOUR ZONE>
    export MACHINE_TYPE=g4-standard-48
    export ACCELERATOR=nvidia-rtx-pro-6000
    export GPU_COUNT=1
    ```

3. Create GCP instance
    ``` 
    gcloud compute instances create my-vss-vm \
     --project=${PROJECT_ID} \
     --location=${ZONE} \
     --machine-type=${MACHINE_TYPE} \
     --accelerator=type=${ACCELERATOR},count=${GPU_COUNT} \
     --image-family=ubuntu-2204-lts \
     --image-project=ubuntu-os-cloud \
     --maintenance-policy=TERMINATE \
     --boot-disk-size=500GB
     --tags=http-server,https-server 
    ```
    or manually create a VM through GCP console UI, with an external IP address.

4. Create firewall rule to allow SSH on the instance:
    ```
    gcloud compute --project=${PROJECT_ID} firewall-rules create vss-blueprint-access --direction=INGRESS --priority=1000 --network=VPC_NETWORK --action=ALLOW --rules=tcp:22 --source-ranges=[YOUR IP or 0.0.0.0/0] --target-tags=http-server,https-server
    ```

## Task 2. Configure NVIDIA NGC API Key
First, ssh in your newly created VM.

```
# Install microk8s
sudo snap install microk8s --classic
# Enable nvidia and hostpath-storage add-ons
sudo microk8s enable nvidia
sudo microk8s enable hostpath-storage
# Install kubectl
sudo snap install kubectl --classic
# Verify microk8s is installed correctly
sudo microk8s kubectl get pod -A
```

```
# Export NGC_API_KEY

export NGC_API_KEY=<YOUR_LEGACY_NGC_API_KEY>

# Export HF_TOKEN

export HF_TOKEN=<YOUR_HUGGING_FACE_TOKEN>

# Create credentials for pulling images from NGC (nvcr.io)

sudo microk8s kubectl create secret docker-registry ngc-docker-reg-secret \
    --docker-server=nvcr.io \
    --docker-username='$oauthtoken' \
    --docker-password=$NGC_API_KEY

# Configure login information for Neo4j graph database

sudo microk8s kubectl create secret generic graph-db-creds-secret \
    --from-literal=username=neo4j --from-literal=password=password

# Configure login information for ArangoDB graph database
# Note: Need to keep username as root for ArangoDB to work.

sudo microk8s kubectl create secret generic arango-db-creds-secret \
    --from-literal=username=root --from-literal=password=password

# Configure login information for MinIO object storage

sudo microk8s kubectl create secret generic minio-creds-secret \
    --from-literal=access-key=minio --from-literal=secret-key=minio123

# Configure the legacy NGC API key for downloading models from NGC

sudo microk8s kubectl create secret generic ngc-api-key-secret \
--from-literal=NGC_API_KEY=$NGC_API_KEY

# Configure the Hugging Face token for downloading models from Hugging Face
sudo microk8s kubectl create secret generic hf-token-secret \
--from-literal=HF_TOKEN=$HF_TOKEN
```

Check you have NVIDIA driver 580.65.06 (Recommended minimum version) and CUDA 13.0+ (CUDA driver installed with NVIDIA driver) with ```nvidia-smi```

## Task 3. Deploying the VSS blueprint on the VM
Still in your VM, run : 

1. Fetch NIM LLM Helm Chart:
    ```
    sudo microk8s helm fetch \
    https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-vss-2.4.1.tgz \
    --username='$oauthtoken' --password=$NGC_API_KEY
    ```

2. Create the override file to allow for single GPU deployment (this is where you can also customize and choose which VLM model to use). An overrides.yaml file is provided in this repo.


3. Deploy the blueprint:
    ```
   sudo microk8s helm install vss-blueprint nvidia-blueprint-vss-2.4.1.tgz
    --set global.ngcImagePullSecretName=ngc-docker-reg-secret -f overrides.yaml
    ```
   
   You may check the progress with 
   ```sudo watch -n1 microk8s kubectl get pod```
  
   and when all pods are READY ```sudo microk8s kubectl logs -l app.kubernetes.io/name=vss```
   
   Look for this line at the end of the logs : ```Application startup complete. Uvicorn running on http://0.0.0.0:9000``` 
   or 
```
INFO:     10.78.15.132:48016 - "GET /health/ready HTTP/1.1" 200 OK
INFO:     10.78.15.132:50386 - "GET /health/ready HTTP/1.1" 200 OK
INFO:     10.78.15.132:50388 - "GET /health/live HTTP/1.1" 200 OK
```
   

## Task 4. Interact withe VSS UI
Run the following command and take note of the NodePorts

```bash
sudo microk8s kubectl get svc vss-service
```
__Example output:__
``vss-service  NodePort <CLUSTER_IP> <none>  8000:32114/TCP,9000:32206/TCP  12m``

Using the output, identify the NodePorts:

Port 8000 corresponds to the REST API (`VSS_API_ENDPOINT`); this is mapped to machine’s port 32114

Port 9000 corresponds to the UI; this is mapped to machine’s port 32206

Update the firewall rule (or create a new one) allowing Ingress (from your own IP or 0.0.0.0/0) for ports listed above.

Then in a web browser, go to `http://VM_EXTERNAL_IP:UI_PORT`
and start interacting with your VSS instance!


## Task 5. Cleanup

```bash
sudo microk8s helm uninstall vss-blueprint
```

### Learn More

Be sure to check out the following articles for more information:
* [Google Compute Engine (GCE)](https://docs.cloud.google.com/compute/docs/overview)
* [NVIDIA GPUs](https://cloud.google.com/compute/docs/gpus)
* [NVIDIA AI Enterprise](https://console.cloud.google.com/marketplace/product/nvidia/nvidia-ai-enterprise-vmi)
* [NVIDIA NIMs](https://www.nvidia.com/en-us/ai/)
