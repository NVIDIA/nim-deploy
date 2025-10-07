# Overview

The NVIDIA RAG blueprint serves as a reference solution for a foundational Retrieval Augmented Generation (RAG) pipeline.
One of the key use cases in Generative AI is enabling users to ask questions and receive answers based on their enterprise data corpus.
This blueprint demonstrates how to set up a RAG solution that uses NVIDIA NIM and GPU-accelerated components.

# Key Features

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

# Prerequisites 

- NVIDIA Account and API Key (follow [these instructions](https://nvdam.widen.net/s/tvgjgxrspd/create-build-account-and-api-key) to create an account and generate an API Key)


### Hardware Requirements

The infrastructure provisioning script will automatically create an Azure Kubernetes Service (AKS) cluster with the following resources in the specified region. Ensure your Azure subscription has sufficient quotas for these resources.

* **Cluster Management Node Pool**:
  * **Machine Type**: `Standard_D32s_v5`
  * **Quantity**: 2 nodes (default for control/management)
* **GPU Worker Node Pool**:
  * **Machine Type**: `Standard_NC96ads_A100_v4`
  * **Quantity**: 1 nodes
  * **GPUs per node**: 4 x **NVIDIA A100** (80GB)

You may adjust node counts and machine types in the environment variables to fit your workload and quota limits.


# Task 1: Environment Configuration

### 1. Install AKS Preview extension

1. Open Cloud Shell

Once you log in, click on the Cloud Shell button, located at the top bar:

![Azure_Cloud_Shell.png](imgs/Azure_Cloud_Shell.png)

(Note: if it's not visible, click on the 3 dots):

![Azure_Cloud_Shell_Expand.png](imgs/Azure_Cloud_Shell_Expand.png)

2. When asked, select "Bash"

![Bash.png](imgs/Bash.png)

3. When asked, select "No Storage", the preferred subscription, and click "Apply"

![Subscription.png](imgs/Subscription.png)

4. Run the below commands:

```bash
az extension add --name aks-preview
az extension update --name aks-preview
```

### 2. Configure NVIDIA API Key

As part of the RAG blueprint several NVIDIA NIMs will be deployed. In order to get started with NIM, we'll need to make sure we have access to an [NVIDIA API key](https://org.ngc.nvidia.com/setup/api-key). We can export this key to be used as an environment variable:

```bash
export NGC_API_KEY="<YOUR NGC API KEY>"
```

### 3. Set up environment variables

```bash
export REGION=<PREFERRED_AZURE_REGION>
export RESOURCE_GROUP=<RG-GROUP-NAME>
export CLUSTER_NAME=rag-demo 
export CLUSTER_MACHINE_TYPE=Standard_D32s_v5
export NODE_POOL_MACHINE_TYPE=standard_nc96ads_a100_v4
export NODE_COUNT=1
export CPU_COUNT=2
export CHART_NAME=rag-chart
export NAMESPACE=rag
```

### 4. Create a Resource Group

```bash
az group create -l $REGION -n $RESOURCE_GROUP
```

### 5. Create AKS cluster

```bash
az aks create -g $RESOURCE_GROUP \
    -n $CLUSTER_NAME \
    --location $REGION \
    --node-count $CPU_COUNT \
    --node-vm-size $CLUSTER_MACHINE_TYPE \
    --enable-node-public-ip \
    --generate-ssh-keys
```

### 6. Get AKS cluster credentials

```bash
az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME
```

### 7. Create node pool

```bash
az aks nodepool add --resource-group $RESOURCE_GROUP \
    --cluster-name $CLUSTER_NAME \
    --name gpupool \
    --node-count $NODE_COUNT \
    --gpu-driver none \
    --node-vm-size $NODE_POOL_MACHINE_TYPE \
    --node-osdisk-size 2048 \
    --max-pods 110
```

# Task 2: NVIDIA GPU Operator Installation

### 1. Add the NVIDIA Helm repository

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --pass-credentials && helm repo update
```

### 2. Install the GPU Operator

```bash
helm install --create-namespace --namespace gpu-operator nvidia/gpu-operator --wait --generate-name
```

### 3. Validate the installation 

```bash
kubectl get pods -A -o wide
```

We need to wait until all pods are in "Running" status and their "Ready" column shows all pods ready (e.g. 1/1, 2/2 etc.)

# Task 3: NVIDIA Blueprint Deployment

### 1. Create a Kubernetes namespace

```bash
kubectl create namespace $NAMESPACE
```

### 2. Install the RAG blueprint Helm chart

Note: in order to save GPU resources, we will be deploying the text-only ingestion blueprint.

```bash
helm install rag -n rag https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.2.0.tgz \
  --create-namespace \
  --username '$oauthtoken' \
  --password "${NGC_API_KEY}" \
  --set imagePullSecret.password=$NGC_API_KEY \
  --set ngcApiSecret.password=$NGC_API_KEY \
  --set nim-llm.enabled=true \
  --set nim-llm.image.repository="nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1" \
  --set nim-llm.image.tag="latest" \
  --set nim-llm.resources.limits."nvidia\.com/gpu"=2 \
  --set nim-llm.resources.requests."nvidia\.com/gpu"=2 \
  --set nvidia-nim-llama-32-nv-embedqa-1b-v2.enabled=true \
  --set nvidia-nim-llama-32-nv-embedqa-1b-v2.image.tag="1.3.0" \
  --set nvidia-nim-llama-32-nv-embedqa-1b-v2.resources.limits."nvidia\.com/gpu"=1 \
  --set nvidia-nim-llama-32-nv-embedqa-1b-v2.resources.requests."nvidia\.com/gpu"=1 \
  --set text-reranking-nim.enabled=false \
  --set ingestor-server.enabled=true \
  --set ingestor-server.envVars.APP_VECTORSTORE_ENABLEGPUINDEX="False" \
  --set ingestor-server.envVars.APP_VECTORSTORE_ENABLEGPUSEARCH="False" \
  --set ingestor-server.envVars.APP_NVINGEST_EXTRACTTABLES="False" \
  --set ingestor-server.envVars.APP_NVINGEST_EXTRACTCHARTS="False" \
  --set ingestor-server.envVars.APP_NVINGEST_EXTRACTIMAGES="False" \
  --set ingestor-server.envVars.APP_NVINGEST_EXTRACTINFOGRAPHICS="False" \
  --set ingestor-server.envVars.APP_NVINGEST_ENABLEPDFSPLITTER="False" \
  --set ingestor-server.envVars.APP_NVINGEST_CHUNKSIZE="1024" \
  --set ingestor-server.envVars.NV_INGEST_FILES_PER_BATCH="32" \
  --set ingestor-server.envVars.NV_INGEST_CONCURRENT_BATCHES="8" \
  --set ingestor-server.envVars.ENABLE_MINIO_BULK_UPLOAD="True" \
  --set ingestor-server.envVars.NV_INGEST_DEFAULT_TIMEOUT_MS="5000" \
  --set ingestor-server.nv-ingest.redis.image.repository="bitnamisecure/redis" \
  --set ingestor-server.nv-ingest.redis.image.tag="latest" \
  --set ingestor-server.nv-ingest.envVars.INGEST_DISABLE_DYNAMIC_SCALING="True" \
  --set ingestor-server.nv-ingest.envVars.MAX_INGEST_PROCESS_WORKERS="32" \
  --set ingestor-server.nv-ingest.envVars.NV_INGEST_MAX_UTIL="80" \
  --set ingestor-server.nv-ingest.envVars.INGEST_EDGE_BUFFER_SIZE="128" \
  --set ingestor-server.nv-ingest.milvus.image.all.repository="milvusdb/milvus" \
  --set ingestor-server.nv-ingest.milvus.image.all.tag="v2.5.3" \
  --set ingestor-server.nv-ingest.milvus.standalone.resources.limits."nvidia\.com/gpu"=0 \
  --set ingestor-server.nv-ingest.nemoretriever-page-elements-v2.deployed=true \
  --set ingestor-server.nv-ingest.nemoretriever-graphic-elements-v1.deployed=false \
  --set ingestor-server.nv-ingest.nemoretriever-table-structure-v1.deployed=false \
  --set ingestor-server.nv-ingest.paddleocr-nim.deployed=false \
  --set envVars.ENABLE_RERANKER="False"
```

### 3. Verify that the PODs are running

```bash
kubectl get pods -n $NAMESPACE
```

### **IT CAN TAKE UP TO 20 mins ** for all services to come up. You can continue on next steps in the meantime while you wait. When all services start , it should look like this:
```
user1-54803080 [ ~ ]$ kubectl get pods -n $NAMESPACE
NAME                                                        READY   STATUS    RESTARTS        AGE
ingestor-server-c5f5fd5c7-fmdgm                             1/1     Running   0               13m
milvus-standalone-594df6565-mzzpm                           1/1     Running   5 (8m11s ago)   13m
rag-etcd-0                                                  1/1     Running   0               13m
rag-frontend-547bc85495-svhzm                               1/1     Running   0               13m
rag-minio-f88fb7fd4-2h4sv                                   1/1     Running   0               13m
rag-nim-llm-0																								1/1     Running   0               13m
rag-nv-ingest-795cbb7bfd-b7zql                              1/1     Running   0               13m
rag-nvidia-nim-llama-32-nv-embedqa-1b-v2-576fdc44bb-hmx6j   1/1     Running   0               13m
rag-redis-master-0                                          1/1     Running   0               13m
rag-redis-replicas-0                                        1/1     Running   4 (115s ago)    13m
rag-server-64dd5c74c9-zclj9                                 1/1     Running   0               13m
rag-text-reranking-nim-74d96dc99d-sdghx                     1/1     Running   0               13m
```


# Task 4: Access the RAG Frontend Service

The RAG Playground service exposes a UI that enables interaction with the end to end RAG pipeline. A user submits a prompt or a request and this triggers the chain server to communicate with all the necessary services required to generate output.

We need to take a few steps in order to access the service.

### 1. Accessing the Frontend Service

In order to access the UI, we need to expose an external load balancer service to allow TCP traffic to the service that is running our front end.

We can do this using the following command:

```bash
kubectl -n $NAMESPACE expose deployment rag-frontend --name=rag-frontend-lb --type=LoadBalancer --port=80 --target-port=3000
```

To access the UI of the application, we get the external IP address of the front end load balancer service:

```bash
kubectl -n $NAMESPACE get svc rag-frontend-lb
```

Output should look like this:
```
user1-54803080 [ ~ ]$ kubectl -n $NAMESPACE get svc rag-frontend-lb -w
NAME              TYPE           CLUSTER-IP   EXTERNAL-IP       PORT(S)        AGE
rag-frontend-lb   LoadBalancer   10.0.XX.XX   XX.XX.XX.XX   80:30977/TCP   14s
```

### Before using the RAG app. Verify that all PODs are running:

```bash
kubectl get pods -n $NAMESPACE
```

Open your browser and navigate to: http://EXTERNAL-IP-FROM-YOUR-CLI-RESULT-ABOVE

From here, we should be able to interact with the service and get some outputs from the LLM.

It should look like this:

![rag_front_end.png](imgs/rag_front_end.png)


### 3. Testing the RAG Blueprint

In order to test the RAG capabilities of this application, we need to upload a document:

* Click new collection at the bottom left corner and give it a name
* Upload a Document by clicking in the square under "Source Files", selecting a PDF or text file and clicking "Create Collection"

![upload_popup.png](imgs/upload_popup.png)
* Wait for "Collection Created successfully" notification

![upload_popup_successful.png](imgs/upload_popup_successful.png)

* Close the prompt window, and click the "Test_Collection" checkbox on the left:

![test_collection.png](imgs/test_collection.png)

### 4. Test Nemotron Thinking Capabilities

Try these example prompts to see the advanced reasoning:

* Basic Q&A:

	"What are the main topics covered in this document?"


* Analysis Request:

	"Analyze the key arguments presented and identify any potential weaknesses or gaps."


* Complex Reasoning:

	"Based on the information in this document, what implications does this have for [relevant topic]? Please consider multiple perspectives."