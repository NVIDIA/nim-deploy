
*Disclaimer: This sample is based on this [repository](https://github.com/NVIDIA-AI-Blueprints/rag). For the most up to date information, licensing, and terms of use please refer to it.*

### Overview

The NVIDIA RAG blueprint serves as a reference solution for a foundational Retrieval Augmented Generation (RAG) pipeline.
One of the key use cases in Generative AI is enabling users to ask questions and receive answers based on their enterprise data corpus.
This blueprint demonstrates how to set up a RAG solution that uses NVIDIA NIM and GPU-accelerated components.
By default, this blueprint leverages locally-deployed NVIDIA NIM microservices to meet specific data governance and latency requirements.
However, you can replace these models with your NVIDIA-hosted models available in the [NVIDIA API Catalog](https://build.nvidia.com).

### Key Features
- Multimodal PDF data extraction support with text, tables, charts, and infographics
- Support for audio file ingestion
- Native Python library support
- Custom metadata support
- Multi-collection searchability
- Opt-in for Vision Language Model (VLM) Support in the answer generation pipeline.
- Document summarization
- Hybrid search with dense and sparse search
- Opt-in image captioning with vision language models (VLMs)
- Reranking to further improve accuracy
- GPU-accelerated Index creation and search
- Multi-turn conversations
- Multi-session support
- Telemetry and observability
- Improve accuracy with optional reflection
- Improve content safety with an optional programmable guardrails to
- Sample user interface
- OpenAI-compatible APIs
- Decomposable and customizable

### Note 

- In order to save GPU resources, we will be deploying the [text-only ingestion](https://github.com/NVIDIA-AI-Blueprints/rag/blob/main/docs/text_only_ingest.md) blueprint.
- We will change the LLM from LLama-nemotron 49b to LLama-nemotron-nano-8b.

### Prerequisites

To successfully deploy this blueprint, you'll need the following accounts and tools set up on your local machine:

* **Google Cloud Platform (GCP) Account**: You need a GCP account with an active project. Ensure that **billing is enabled** and the **Google Kubernetes Engine (GKE) API** is activated for your project.
* **NVIDIA NGC Account**: An account is required to get an **NGC API Key** for pulling the necessary container images and Helm charts. You can sign up and generate a key at [ngc.nvidia.com](https://build.nvidia.com).
* **Google Cloud SDK**: The `gcloud` command-line tool must be installed and configured. You should be authenticated (`gcloud auth login`) and have your project set (`gcloud config set project <YOUR_PROJECT_ID>`).
* **kubectl**: The Kubernetes command-line tool is required to interact with the GKE cluster. It can be installed via the Google Cloud SDK by running `gcloud components install kubectl`.
* **Helm**: The package manager for Kubernetes is needed to deploy the blueprint chart.

### Hardware Requirements

The infrastructure provisioning script will automatically create a GKE cluster with the following resources in the `us-central1-b` zone. Ensure your project has sufficient quotas for these resources in that region.

* **Cluster Management Node**:
    * **Machine Type**: `e2-standard-32`
* **GPU Worker Node Pool**:
    * **Quantity**: 1 Node
    * **Machine Type**: `a2-highgpu-4g`
    * **GPUs**: 4 x **NVIDIA A100** (40GB)


### Infrastructure Provisioning

1. Declare NGC API key

```bash
export NGC_API_KEY=<add your key here>
```


2. Set other environment variables:

```bash
export PROJECT_ID=$GOOGLE_CLOUD_PROJECT 
export ZONE=us-central1-b
export CLUSTER_NAME=rag-demo 
export NODE_POOL_MACHINE_TYPE=a2-highgpu-4g
export CLUSTER_MACHINE_TYPE=e2-standard-32
export GPU_TYPE=nvidia-tesla-a100
export GPU_COUNT=4
export WORKLOAD_POOL=$PROJECT_ID.svc.id.goog
export CHART_NAME=rag-chart
export NAMESPACE=rag
```

3. Create cluster

```bash
gcloud container clusters create ${CLUSTER_NAME} \
    --project=${PROJECT_ID} \
    --location=${ZONE} \
    --workload-pool=${WORKLOAD_POOL} \
    --machine-type=${CLUSTER_MACHINE_TYPE} \
    --num-nodes=1
```

4. Create node pool

```bash
gcloud container node-pools create gpupool \
    --accelerator="type=${GPU_TYPE},count=${GPU_COUNT},gpu-driver-version=latest" \
    --project=${PROJECT_ID} \
    --cluster=$CLUSTER_NAME \
    --num-nodes=1 \
    --location=$ZONE \
    --machine-type=$NODE_POOL_MACHINE_TYPE
```

### Blueprint Deployment

1. create kubernetes namespace

```bash
kubectl create ns rag
```

2. install helm chart

```bash
helm upgrade --install rag -n rag https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.2.0.tgz \
  --username '$oauthtoken' \
  --password "${NGC_API_KEY}" \
  --set imagePullSecret.password=$NGC_API_KEY \
  --set ngcApiSecret.password=$NGC_API_KEY \
  -f values.yaml
  ```

3. Verify PODs are running 

```bash
kubectl get pods -n rag
```

4. port forward the frontend service

```bash
kubectl port-forward svc/rag-frontend 8080:3000
```

then navigate to http://localhost:8080 on your browser


### Cleanup

After you have finished, run the following command to delete the GKE cluster and all associated resources to avoid incurring further costs. 🧹

```bash
gcloud container clusters delete $CLUSTER_NAME --zone=$ZONE
```




Of course! Here are the completed "Prerequisites" and "Hardware Requirements" sections for your guide.

***




