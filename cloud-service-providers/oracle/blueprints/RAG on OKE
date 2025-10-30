# Deploy the NVIDIA RAG Pipeline Blueprint on Oracle Kubernetes Engine (OKE)

This guide provides comprehensive step-by-step instructions for deploying the NVIDIA Retrieval Augmented Generation (RAG) Pipeline Blueprint on Oracle Cloud Infrastructure (OCI) using Oracle Kubernetes Engine (OKE) with GPU instances. The RAG Blueprint combines NVIDIA NIM (Inference Microservices), NeMo Retriever, and vector databases to create a production-ready document Q&A system.

---

## Prerequisites

Before starting the deployment process, ensure you have the following:

- An active OCI account with appropriate permissions
- OCI CLI installed and configured on your local machine
- kubectl installed and configured
- Helm 3.x installed
- NVIDIA NGC API key (from [NGC](https://ngc.nvidia.com)) to access NVIDIA's container registry
- Access to GPU compute shapes (A100, H100, or A10) in your OCI tenancy
- Familiarity with Kubernetes and OKE

---

## IAM Policy Requirements

The deployment requires specific OCI Identity and Access Management (IAM) permissions. Ensure your user/group has the following permissions:

### User/Group Policies

```text
Allow group <GROUP_NAME> to manage instance-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to manage cluster-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to manage virtual-network-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to use subnets in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to manage load-balancers in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to manage volume-family in compartment <COMPARTMENT_NAME>
```

### Service Policies for OKE

```text
Allow service OKE to manage all-resources in compartment <COMPARTMENT_NAME>
```

---

## Infrastructure Setup

This section covers creating your OKE cluster with GPU nodes. OKE Quick Create will automatically set up all required networking.

---

## 1. Create OKE Cluster Using Quick Create
**Simplest way to provision your Kubernetes cluster with automatic networking**

### 1.1 Navigate to OKE

1. Open the **OCI Console** in your browser
2. Click the **hamburger menu** (☰) in the top-left corner
3. Navigate to **Developer Services** → **Kubernetes Clusters (OKE)**
4. Ensure you're in the correct **Compartment** (use the compartment dropdown on the left)

### 1.2 Create Cluster with Quick Create

1. Click the **Create cluster** button

2. **Select Creation Method**:
   - Choose **Quick Create** 
   - Click **Submit**

> **Note:** Quick Create automatically creates the VCN, subnets, gateways, route tables, and security lists for you. This is the simplest option for workshops.

3. **Basic Information**:
   - **Name**: `RAG-OKE-Cluster`
   - **Compartment**: Select your compartment
   - **Kubernetes version**: Select latest stable (e.g., `v1.30.1`)
   - **Kubernetes API endpoint**: **Public endpoint** (default)
   - **Kubernetes worker nodes**: **Private workers** (default)

4. **Quick Create will automatically configure**:
   - New VCN with appropriate CIDR ranges
   - Public subnet for LoadBalancers and API endpoint
   - Private subnet for worker nodes
   - Internet Gateway for public subnet
   - NAT Gateway for private subnet
   - Service Gateway for OCI services
   - Route tables and security lists

> **Security Note:** Quick Create will configure security lists with `0.0.0.0/0` for some rules. **This is NOT recommended for production.** After cluster creation, review and restrict security rules to your specific IP ranges or corporate network CIDR blocks.

5. **Node Pool Shape and Configuration** - Scroll down to configure GPU nodes

---

## 2. Configure GPU Node Pool
**Setting up the GPU-equipped worker nodes**

Continue in the Quick Create wizard - scroll down to the Node Pool section:

### 2.1 Node Pool Shape and Size

1. **Shape**:
   - Click **Change shape**
   - Select **Bare Metal** tab
   - Search for and select: **BM.GPU.A100-v2.8**
     - 8x NVIDIA A100 GPUs
     - 160 OCPUs
     - 2048 GB Memory
   - Click **Select shape**

2. **Number of nodes**: `1`

3. **Node Pool Name**: Leave default or enter `GPU-Node-Pool`

### 2.2 Configure Advanced Settings (CRITICAL)

Click **Show advanced options** to expand additional settings:

1. **Boot volume size**: `1000` GB (minimum)

2. **Maximum number of pods per node**: 
   - Scroll to find this setting
   - Change from default (31) to: **`50`** or higher
   
   > **CRITICAL:** The full RAG Blueprint deployment requires at least 50 pods per node to avoid scheduling issues. The default value of 31 is insufficient and will cause pod placement failures.

3. **SSH Keys**:
   - **Paste SSH keys** or **Upload public key file(s)**
   - Add your SSH public key for node access (optional but recommended)

### 2.3 Review and Create

1. Review all settings on the summary page
2. Click **Create cluster** at the bottom
3. Wait for cluster creation to complete

**Expected Status:**
- Initial state: **Creating** (7-10 minutes)
- Cluster state: **Active** 
- Node pool state: **Creating** then **Active** (total 15-20 minutes)

You can monitor progress on the cluster details page. The page will automatically refresh.

### 2.4 Verify Cluster Creation

Once the cluster shows **Active** status:

1. On the cluster details page, verify:
   - **State**: Active (green checkmark)
   - **Kubernetes version**: v1.30.1
   - **Kubernetes API endpoint**: Shows a public URL
   - **VCN**: Automatically created VCN name

2. Click on **Node Pools** in the left menu
3. Verify your GPU node pool:
   - **State**: Active
   - **Nodes**: 1
   - **Node Shape**: BM.GPU.A100-v2.8
   - **Kubernetes version**: v1.30.1

**Note:** If the node pool is still creating, wait until it shows **Active** before proceeding. This can take 15-20 minutes total.

---

## 3. Configure kubectl Access
**Setting up cluster access from the Console**

### 3.1 Access Cluster from Console

1. In the OCI Console, navigate to your cluster: **RAG-OKE-Cluster**
2. Click the **Access Cluster** button at the top of the cluster details page

3. In the **Access Your Cluster** dialog:
   - Select **Cloud Shell Access** (easiest option) or **Local Access**

### 3.2 Option A: Cloud Shell Access (Recommended)

1. Click **Launch Cloud Shell** button
2. Cloud Shell will open at the bottom of your browser
3. Copy and paste the provided command (similar to):

```bash
oci ce cluster create-kubeconfig \
  --cluster-id ocid1.cluster.oc1..<unique_id> \
  --file $HOME/.kube/config \
  --region <YOUR_REGION> \
  --token-version 2.0.0 \
  --kube-endpoint PUBLIC_ENDPOINT
```

> **Note:** The actual command will have your specific cluster OCID and region. Copy it exactly as shown in the console.

4. Press Enter to execute the command

**Expected Output:**
```
New config written to the Kubeconfig file /home/your_username/.kube/config
```

### 3.3 Option B: Local Access

If using your local machine:

1. Ensure OCI CLI is installed and configured
2. Copy the command from the **Local Access** tab:

```bash
oci ce cluster create-kubeconfig \
  --cluster-id <YOUR_CLUSTER_OCID> \
  --file $HOME/.kube/config \
  --region <YOUR_REGION> \
  --token-version 2.0.0 \
  --kube-endpoint PUBLIC_ENDPOINT
```

> **Note:** Replace `<YOUR_CLUSTER_OCID>` and `<YOUR_REGION>` with your actual values from the console.

3. Run the command in your local terminal

### 3.4 Verify kubectl Access

In Cloud Shell or your local terminal:

```bash
kubectl get nodes
```

**Expected Output:**
```
NAME         STATUS   ROLES   AGE   VERSION
10.0.10.12   Ready    node    5m    v1.30.1
```

**Check node details:**

```bash
kubectl get nodes -o wide
```

**Expected Output:**
```
NAME         STATUS   ROLES   AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                  KERNEL-VERSION
10.0.10.12   Ready    node    5m    v1.30.1   10.0.10.12    <none>        Oracle Linux Server 8.10  5.15.0-200.131.27.el8uek.x86_64
```

---

## 4. Verify GPU Availability
**Confirming GPU resources on nodes**

```bash
kubectl describe nodes | grep nvidia.com/gpu
```

**Expected Output:**
```
nvidia.com/gpu:             8
nvidia.com/gpu.memory:      655360
nvidia.com/gpu.product:     A100-SXM4-80GB
```

---

## 5. Install NVIDIA GPU Operator (If Needed)
**Enabling GPU support in Kubernetes**

```bash
# Add NVIDIA Helm repository
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update

# Install GPU Operator (if not pre-installed on OKE)
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace \
  --set operator.defaultRuntime=crio
```

**Expected Output:**
```
NAME: gpu-operator
LAST DEPLOYED: Thu Oct 30 12:00:00 2025
NAMESPACE: gpu-operator
STATUS: deployed
REVISION: 1
```

**Verify GPU Operator:**

```bash
kubectl get pods -n gpu-operator
```

**Expected Output:**
```
NAME                                                   READY   STATUS    RESTARTS   AGE
gpu-feature-discovery-xxxxx                            1/1     Running   0          2m
gpu-operator-xxxxx                                     1/1     Running   0          3m
nvidia-container-toolkit-daemonset-xxxxx               1/1     Running   0          2m
nvidia-dcgm-exporter-xxxxx                             1/1     Running   0          2m
nvidia-device-plugin-daemonset-xxxxx                   1/1     Running   0          2m
```

---

## 6. Set NGC API Key

Before deploying, export your NGC API key as an environment variable:

```bash
export NGC_API_KEY="<YOUR_NGC_API_KEY>"
```

> **Note:** Replace `<YOUR_NGC_API_KEY>` with your actual NGC API key from [NGC](https://ngc.nvidia.com). The helm chart will automatically create the required secrets using this environment variable.

---

## 7. RAG Deployment Configurations

The RAG Blueprint supports multiple deployment configurations optimized for different use cases and resource requirements. Choose the configuration that best fits your needs:

---

### Configuration 1: Full Blueprint - 8 GPUs, Milvus on CPU
**Complete RAG pipeline with all features, optimized for versatility**

**Resource Requirements:**
- **GPUs**: 8 A100 (80GB each)
- **GPU Allocation**:
  - LLM (Llama 3.1 70B): 2 GPUs
  - Embedding Model: 1 GPU
  - Reranker: 1 GPU
  - NeMo Retriever (Page Elements): 1 GPU
  - NeMo Retriever (Graphics): 1 GPU
  - NeMo Retriever (Tables): 1 GPU
  - PaddleOCR: 1 GPU
- **Vector Database**: Milvus (CPU mode)
- **Pods**: ~40-45 pods total (requires **max pods per node ≥ 50**)

> **Important:** Ensure your node pool is configured with **"Maximum number of pods per node"** set to at least **50**. The default value of 31 will cause deployment failures.

### Deploy:

```bash
helm install rag \
  https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.3.0.tgz \
  --namespace default \
  --set imagePullSecret.password=$NGC_API_KEY \
  --set ngcApiSecret.password=$NGC_API_KEY \
  --set nim-llm.resources.limits."nvidia\.com/gpu"=2 \
  --set nim-llm.resources.requests."nvidia\.com/gpu"=2 \
  --set nv-ingest.milvus.image.all.repository=docker.io/milvusdb/milvus \
  --set nv-ingest.milvus.image.tools.repository=docker.io/milvusdb/milvus-config-tool \
  --set nv-ingest.milvus.standalone.resources.limits."nvidia\.com/gpu"=0 \
  --set nv-ingest.milvus.standalone.resources.requests."nvidia\.com/gpu"=0 \
  --set nv-ingest.milvus.minio.image.repository=docker.io/minio/minio \
  --set ingestor-server.envVars.APP_VECTORSTORE_ENABLEGPUINDEX=False \
  --set ingestor-server.envVars.APP_VECTORSTORE_ENABLEGPUSEARCH=False \
  --set frontend.service.type=LoadBalancer
```

**Expected Output:**
```
Release "rag" does not exist. Installing it now.
NAME: rag
LAST DEPLOYED: Thu Oct 30 12:15:00 2025
NAMESPACE: default
STATUS: deployed
REVISION: 1
```

**Use Cases:**
- Multi-modal document processing (text, images, tables, charts)
- Enterprise documents with complex layouts
- Maximum accuracy and feature completeness

---

### Configuration 2: Text-Only Deployment - 4 GPUs
**Optimized for text-based documents with cost efficiency**

**Resource Requirements:**
- **GPUs**: 4 A100 (80GB each)
- **GPU Allocation**:
  - LLM (Llama 3.1 70B): 2 GPUs
  - Embedding Model: 1 GPU
  - NeMo Retriever (Page Elements): 1 GPU
- **Vector Database**: Milvus (CPU mode)
- **Disabled Components**: Graphics extraction, table extraction, OCR, reranker

### Deploy:

```bash
helm install rag \
  https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.3.0.tgz \
  --namespace default \
  --set imagePullSecret.password=$NGC_API_KEY \
  --set ngcApiSecret.password=$NGC_API_KEY \
  --set nim-llm.resources.limits."nvidia\.com/gpu"=2 \
  --set nim-llm.resources.requests."nvidia\.com/gpu"=2 \
  --set nv-ingest.milvus.image.all.repository=docker.io/milvusdb/milvus \
  --set nv-ingest.milvus.image.tools.repository=docker.io/milvusdb/milvus-config-tool \
  --set nv-ingest.milvus.standalone.resources.limits."nvidia\.com/gpu"=0 \
  --set nv-ingest.milvus.standalone.resources.requests."nvidia\.com/gpu"=0 \
  --set nv-ingest.milvus.minio.image.repository=docker.io/minio/minio \
  --set ingestor-server.envVars.APP_VECTORSTORE_ENABLEGPUINDEX=False \
  --set ingestor-server.envVars.APP_VECTORSTORE_ENABLEGPUSEARCH=False \
  --set nv-ingest.nemoretriever-graphic-elements-v1.deployed=false \
  --set nv-ingest.nemoretriever-table-structure-v1.deployed=false \
  --set nv-ingest.paddleocr-nim.deployed=false \
  --set nv-ingest.nemoretriever-ocr.deployed=false \
  --set nvidia-nim-llama-32-nv-rerankqa-1b-v2.enabled=false \
  --set frontend.service.type=LoadBalancer
```

**Expected Output:**
```
Release "rag" does not exist. Installing it now.
NAME: rag
LAST DEPLOYED: Thu Oct 30 12:15:00 2025
NAMESPACE: default
STATUS: deployed
REVISION: 1
```

**Use Cases:**
- Text-heavy documents (articles, reports, manuals)
- Cost-optimized deployments
- Development and testing
- 50% GPU cost reduction vs full blueprint

---

### Configuration 3: Nemotron Nano 9B - 8 GPUs, Milvus on GPU
**Lightweight model with GPU-accelerated vector search**

**Resource Requirements:**
- **GPUs**: 8 A100 (80GB each) or 8 A10 (24GB each)
- **GPU Allocation**:
  - LLM (Nemotron Nano 9B): 1 GPU (~18GB)
  - Embedding Model: 1 GPU (~2GB)
  - Milvus Vector DB: 1 GPU
  - NeMo Retriever Services: 5 GPUs
- **Vector Database**: Milvus (GPU-accelerated mode)

> **A10 Compatible:** This configuration can use the smaller Nemotron Nano 9B model which fits on A10 GPUs (24GB). This is the most cost-effective configuration that works with A10.

### Deploy:

```bash
helm install rag \
  https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.3.0.tgz \
  --namespace default \
  --set imagePullSecret.password=$NGC_API_KEY \
  --set ngcApiSecret.password=$NGC_API_KEY \
  --set nim-llm.image.repository=nvcr.io/nim/nvidia/nvidia-nemotron-nano-9b-v2 \
  --set nim-llm.image.tag=latest \
  --set nim-llm.model.name="nvidia/nvidia-nemotron-nano-9b-v2" \
  --set envVars.APP_LLM_MODELNAME="nvidia/nvidia-nemotron-nano-9b-v2" \
  --set nv-ingest.milvus.image.all.repository=docker.io/milvusdb/milvus \
  --set nv-ingest.milvus.image.tools.repository=docker.io/milvusdb/milvus-config-tool \
  --set nv-ingest.milvus.minio.image.repository=docker.io/minio/minio \
  --set frontend.service.type=LoadBalancer
```

**Expected Output:**
```
Release "rag" does not exist. Installing it now.
NAME: rag
LAST DEPLOYED: Thu Oct 30 12:15:00 2025
NAMESPACE: default
STATUS: deployed
REVISION: 1
```

**Use Cases:**
- Lower latency requirements
- Faster inference with smaller model
- GPU-accelerated vector similarity search
- High-throughput document ingestion

---

### Configuration 4: VLM Full Blueprint - Multi-Modal with Vision
**Complete multi-modal RAG with vision language model**

**Resource Requirements:**
- **GPUs**: 8 A100 (80GB each) or 8 A10 (24GB each)
- **GPU Allocation**:
  - LLM (Nemotron Nano 9B): 1 GPU (~18GB)
  - VLM (Nemotron Nano VL 8B): 2 GPUs (~16GB each)
  - Embedding Model: 1 GPU (~2GB)
  - NeMo Retriever Services: 4 GPUs
- **Vector Database**: Milvus (CPU mode)
- **Special Features**: Vision-Language Model for image understanding

> **A10 Compatible:** This configuration uses Nano models (9B LLM + 8B VLM) which fit on A10 GPUs (24GB). Provides multi-modal capabilities at lower cost.

### Deploy:

```bash
helm install rag \
  https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.3.0.tgz \
  --namespace default \
  --set imagePullSecret.password=$NGC_API_KEY \
  --set ngcApiSecret.password=$NGC_API_KEY \
  --set nim-llm.image.repository=nvcr.io/nim/nvidia/nvidia-nemotron-nano-9b-v2 \
  --set nim-llm.image.tag=latest \
  --set nim-llm.model.name="nvidia/nvidia-nemotron-nano-9b-v2" \
  --set envVars.APP_LLM_MODELNAME="nvidia/nvidia-nemotron-nano-9b-v2" \
  --set nim-vlm.enabled=true \
  --set envVars.ENABLE_VLM_INFERENCE=true \
  --set envVars.APP_VLM_MODELNAME="nvidia/llama-3.1-nemotron-nano-vl-8b-v1" \
  --set envVars.APP_VLM_SERVERURL="http://nim-vlm:8000/v1" \
  --set nv-ingest.milvus.image.all.repository=docker.io/milvusdb/milvus \
  --set nv-ingest.milvus.image.tools.repository=docker.io/milvusdb/milvus-config-tool \
  --set nv-ingest.milvus.standalone.resources.limits."nvidia\.com/gpu"=0 \
  --set nv-ingest.milvus.standalone.resources.requests."nvidia\.com/gpu"=0 \
  --set nv-ingest.milvus.minio.image.repository=docker.io/minio/minio \
  --set ingestor-server.envVars.APP_VECTORSTORE_ENABLEGPUINDEX=False \
  --set ingestor-server.envVars.APP_VECTORSTORE_ENABLEGPUSEARCH=False \
  --set frontend.service.type=LoadBalancer
```

**Expected Output:**
```
Release "rag" does not exist. Installing it now.
NAME: rag
LAST DEPLOYED: Thu Oct 30 12:15:00 2025
NAMESPACE: default
STATUS: deployed
REVISION: 1
```

**Use Cases:**
- Documents with images, diagrams, and charts
- Visual question answering
- Multi-modal understanding (text + vision)
- Complex document layouts requiring visual reasoning

---

## Configuration Comparison

| Feature | Config 1: Full | Config 2: Text-Only | Config 3: Nano + GPU Milvus | Config 4: VLM |
|---------|----------------|---------------------|------------------------------|---------------|
| **GPU Count** | 8 | 4 | 8 | 8 |
| **LLM Model** | Llama 3.1 70B | Llama 3.1 70B | Nemotron Nano 9B | Nemotron Nano 9B |
| **Vision Model** | No | No | No | Yes - Nano VL 8B |
| **Image Processing** | Full | No | Full | Enhanced |
| **Table Extraction** | Yes | No | Yes | Yes |
| **OCR** | Yes | No | Yes | Yes |
| **Reranker** | Yes | No | Yes | Yes |
| **Milvus Mode** | CPU | CPU | GPU | CPU |
| **A10 Compatible** | No | No | Yes | Yes |
| **Min GPU Memory** | 80GB | 80GB | 24GB | 24GB |
| **Best For** | Enterprise | Dev/Test | Low Latency | Multi-Modal |
| **Cost** | Highest | Lowest | Medium | Medium |

---

## 8. Monitor Deployment
**Watching the deployment progress**

```bash
kubectl get pods
```

**Expected Output (All pods Running):**
```
NAME                                                     READY   STATUS    RESTARTS   AGE
ingestor-server-xxxxx                                    1/1     Running   0          20m
milvus-standalone-xxxxx                                  1/1     Running   0          20m
rag-etcd-0                                               1/1     Running   0          20m
rag-frontend-xxxxx                                       1/1     Running   0          20m
rag-minio-xxxxx                                          1/1     Running   0          20m
rag-nemoretriever-graphic-elements-xxxxx                 1/1     Running   0          20m
rag-nemoretriever-page-elements-xxxxx                    1/1     Running   0          20m
rag-nemoretriever-table-structure-xxxxx                  1/1     Running   0          20m
rag-nim-llm-0                                            1/1     Running   0          20m
rag-nv-ingest-xxxxx                                      1/1     Running   0          20m
rag-nvidia-nim-llama-32-nv-embedqa-1b-v2-xxxxx           1/1     Running   0          20m
rag-paddleocr-nim-xxxxx                                  1/1     Running   0          20m
rag-redis-master-0                                       1/1     Running   0          20m
rag-redis-replicas-0                                     1/1     Running   0          20m
rag-server-xxxxx                                         1/1     Running   0          20m
rag-text-reranking-nim-xxxxx                             1/1     Running   0          20m
```

---

## 9. Access RAG Playground
**Getting the frontend URL**

```bash
# Get the frontend URL
echo "Frontend: http://$(kubectl get svc rag-frontend -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):3000"
```

**Expected Output:**
```
Frontend: http://XXX.XXX.XXX.XXX:3000
```

> **Security Warning:** The LoadBalancer created by default is accessible from the internet (`0.0.0.0/0`). For production deployments, restrict access by updating the security list to allow only specific IP ranges (your corporate network or VPN).

Open this URL in your browser to access the RAG Playground interface.

---

## 10. Verify RAG Playground Interface
**Confirming the UI is accessible**

You should see the **RAG Playground** interface with:

1. **Chat Interface**: 
   - Message input box
   - Send button
   - Chat history display

2. **Document Management**:
   - Upload documents button
   - Document list
   - Delete documents option

3. **Collection Management**:
   - Create new collection
   - Select active collection
   - Collection dropdown menu

4. **Settings**:
   - Model selection
   - Temperature control
   - Max tokens setting

---

## 11. Test RAG Functionality
**Uploading documents and querying**

### 11.1 Create a Collection and Upload Documents

1. **Create a New Collection**:
   - Click **"New Collection"** button
   - Enter collection name: `test-docs`
   - Click **"Create"**

2. **Download Sample Document**:
```bash
# Download Oracle OCI Supercluster PDF
wget https://www.oracle.com/a/ocom/docs/cloud/accelerate-ai-with-oci-supercluster.pdf \
  -O accelerate-ai-with-oci-supercluster.pdf
```

3. **Upload Document**:
   - Click **"Upload Documents"**
   - Select `accelerate-ai-with-oci-supercluster.pdf`
   - Click **"Upload"**
   - Wait for processing (~30-60 seconds)

**Expected Processing Steps:**
```
1. Uploading document... ✓
2. Extracting text and images... ✓
3. Generating embeddings... ✓
4. Storing in vector database... ✓
5. Document ready for queries ✓
```

---

### 11.2 Query Your Documents

1. **Select Collection**: Choose `test-docs` from dropdown
2. **Enter Query**: Type in chat box:
   - "What is Oracle OCI Supercluster?"
   - "What GPUs are available in the supercluster?"
   - "What are the benefits mentioned in the document?"

3. **Send Query**: Click **Send** or press Enter

**Expected Response Format:**
```
Answer: Oracle OCI Supercluster is a next-generation AI infrastructure 
that provides massive scale compute power for training and deploying 
large language models and other AI workloads. It features NVIDIA H100 
GPUs connected via high-speed RDMA networking...

Sources:
- accelerate-ai-with-oci-supercluster.pdf (Page 1, Chunk 3)
- accelerate-ai-with-oci-supercluster.pdf (Page 2, Chunk 1)
```

---

## 12. Monitor GPU Utilization (Optional)
**Tracking GPU usage across the cluster**

### Option 1: Check GPU allocation per pod (Recommended)

> **Note:** This command requires `jq` to be installed. Cloud Shell has it pre-installed.

```bash
echo "GPU Utilization:" && \
echo "================" && \
kubectl get pods -n default -o json | jq -r '.items[] | select(.spec.containers[].resources.limits."nvidia.com/gpu" != null and .status.phase == "Running") | "\(.spec.containers[0].resources.limits."nvidia.com/gpu") GPU - \(.metadata.name)"' | grep -v "^0 GPU" | sort -rn && \
echo "" && \
kubectl get pods -n default -o json | jq '[.items[] | select(.spec.containers[].resources.limits."nvidia.com/gpu" != null and .status.phase == "Running") | (.spec.containers[0].resources.limits."nvidia.com/gpu" | tonumber)] | add' | awk '{print "Total GPUs Used: " $1}'
```

**Expected Output:**
```
GPU Utilization:
================
2 GPU - rag-nim-llm-0
1 GPU - rag-nvidia-nim-llama-32-nv-embedqa-1b-v2-xxxxx
1 GPU - rag-nemoretriever-graphic-elements-xxxxx
1 GPU - rag-nemoretriever-page-elements-xxxxx
1 GPU - rag-nemoretriever-table-structure-xxxxx
1 GPU - rag-paddleocr-nim-xxxxx
1 GPU - rag-text-reranking-nim-xxxxx

Total GPUs Used: 8
```

### Option 2: Check all GPU allocations across the cluster

```bash
# See GPU resource allocation per node
kubectl describe nodes | grep -A 10 "Allocated resources"
```

**Expected Output:**
```
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests      Limits
  --------           --------      ------
  cpu                12800m (8%)   25600m (16%)
  memory             98304Mi (30%) 131072Mi (40%)
  nvidia.com/gpu     8             8
```
---

## Troubleshooting

Common issues and solutions when deploying RAG on OKE.

---

### Common Problems & Fixes

#### Pods Stuck in Pending

```bash
kubectl describe pod <pod-name>
```

**Expected Output (GPU resource issue):**
```
Events:
  Type     Reason            Message
  ----     ------            -------
  Warning  FailedScheduling  0/1 nodes are available: Insufficient nvidia.com/gpu.
```

**Expected Output (Pod limit reached):**
```
Events:
  Type     Reason            Message
  ----     ------            -------
  Warning  FailedScheduling  0/1 nodes are available: Too many pods.
```

**Solutions:**
```bash
# Check GPU resources
kubectl describe nodes | grep -A5 "Allocated resources"

# Check if GPUs are available
kubectl get nodes -o json | jq '.items[].status.allocatable'

# Check pod capacity and current pod count
kubectl describe nodes | grep -A5 "Capacity:"
kubectl describe nodes | grep -A5 "Allocatable:"
kubectl get pods --all-namespaces | wc -l
```

**If you see "Too many pods" error:**

The node has reached its maximum pod capacity. For the full RAG Blueprint, you need at least 50 pods per node.

**To fix this issue:**
1. Delete the current node pool
2. Create a new node pool with **"Maximum number of pods per node"** set to **50** or higher (see Section 2.2)
3. Redeploy the RAG Blueprint

**Check current max pods setting:**
```bash
kubectl get nodes -o jsonpath='{.items[*].status.capacity.pods}'
```

**Expected Output for RAG Blueprint:**
```
50
```

If the output shows `31` (default) or less, you need to recreate the node pool with a higher pod limit.

---

#### ImagePullBackOff Errors

```bash
kubectl describe pod <pod-name> | grep -A10 Events
```

**Expected Output:**
```
Events:
  Warning  Failed     Failed to pull image "nvcr.io/...": unauthorized
```

**Solutions:**
```bash
# Verify NGC_API_KEY environment variable is set
echo $NGC_API_KEY

# If not set, export it again
export NGC_API_KEY="<YOUR_NGC_API_KEY>"

# Delete and redeploy the helm chart to recreate secrets
helm uninstall rag --namespace default
helm install rag \
  https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.3.0.tgz \
  --namespace default \
  --set imagePullSecret.password=$NGC_API_KEY \
  --set ngcApiSecret.password=$NGC_API_KEY \
  [... add remaining configuration options ...]
```

---

#### GPU Not Detected

```bash
# Check GPU operator installation
kubectl get pods -n gpu-operator

# Check node labels
kubectl get nodes --show-labels | grep nvidia
```

**Expected Output:**
```
nvidia.com/cuda.driver.major=535
nvidia.com/cuda.driver.minor=104
nvidia.com/cuda.driver.rev=05
nvidia.com/cuda.runtime.major=12
nvidia.com/cuda.runtime.minor=2
nvidia.com/gpu.count=8
nvidia.com/gpu.product=A100-SXM4-80GB
```

**Solutions:**
```bash
# Reinstall GPU operator if needed
helm uninstall gpu-operator -n gpu-operator
kubectl delete namespace gpu-operator

# Reinstall
helm install gpu-operator nvidia/gpu-operator \
  --namespace gpu-operator \
  --create-namespace
```

---

#### LoadBalancer Service Pending

```bash
kubectl get svc rag-frontend
```

**Expected Output (stuck):**
```
NAME           TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)          AGE
rag-frontend   LoadBalancer   10.96.45.123   <pending>     3000:32456/TCP   10m
```

**Solutions:**
```bash
# Check load balancer events
kubectl describe svc rag-frontend

# Ensure public subnet is properly configured
oci network subnet get --subnet-id <SUBNET_OCID>

# Verify service policy for load balancers
oci iam policy list --compartment-id <COMPARTMENT_OCID>
```

---

#### Milvus Pod CrashLoopBackOff

```bash
kubectl logs milvus-standalone-xxxxx
```

**Expected Output:**
```
Error: insufficient memory
Error: failed to create index
```

**Solutions:**
```bash
# Check Milvus resource limits
kubectl get pod milvus-standalone-xxxxx -o yaml | grep -A5 resources

# Increase Milvus memory (if needed)
helm upgrade rag \
  https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.3.0.tgz \
  --reuse-values \
  --set nv-ingest.milvus.standalone.resources.limits.memory=16Gi
```

---

#### Document Upload Fails

```bash
kubectl logs ingestor-server-xxxxx
```

**Expected Output:**
```
Error: Failed to connect to nv-ingest service
Error: Timeout waiting for embedding model
```

**Solutions:**
```bash
# Check all NV-Ingest components
kubectl get pods | grep nv-ingest
kubectl get pods | grep embed

# Check service connectivity
kubectl get svc | grep ingest
kubectl get svc | grep embed

# Restart ingestor if needed
kubectl rollout restart deployment ingestor-server
```

---

## Deployment Checklist

Ensure the following are complete:

- [ ] **OKE cluster** is active and accessible
- [ ] **GPU node pool** with A100/H100 GPUs is ready
- [ ] **Max pods per node** set to **50 or higher** (required for full blueprint)
- [ ] **kubectl** configured and working
- [ ] **NGC_API_KEY** environment variable exported
- [ ] **Helm chart** deployed successfully
- [ ] **All pods** are in Running state (15-20 min wait)
- [ ] **LoadBalancer** has external IP assigned
- [ ] **RAG Playground** UI is accessible
- [ ] **Document upload** works successfully
- [ ] **Query responses** include source citations

### Verification Commands

```bash
# 1. Check cluster status
kubectl cluster-info

# 2. Verify GPU nodes
kubectl get nodes -l nvidia.com/gpu.present=true

# 3. Verify max pods per node (should be 50 or higher)
kubectl get nodes -o jsonpath='{.items[*].status.capacity.pods}'

# 4. Check all pods
kubectl get pods --all-namespaces

# 5. Verify RAG deployment
helm list

# 6. Get frontend URL
echo "Frontend: http://$(kubectl get svc rag-frontend -n default -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):3000"

```

All commands should return successful responses.

**Expected Output for Max Pods Check:**
```
50
```

If the output shows less than 50 (e.g., `31`), the full RAG Blueprint deployment will fail due to insufficient pod capacity.

---

## GPU Compatibility

### OCI GPU Shape Comparison - Preference Ranking

> **Recommendation:** Use **H100** or **A100** GPUs for optimal performance and compatibility.

| Preference Rank | GPU Model | Memory | Shape Name | RAG Compatibility | Performance | Use For |
|-----------------|-----------|--------|------------|-------------------|-------------|---------|
| **1 - BEST** | **H100** | **80 GB** | `BM.GPU.H100.8` | **Excellent** | **Fastest** | **Production, all configs, largest models** |
| **2 - RECOMMENDED** | **A100** | **80 GB** | `BM.GPU.A100-v2.8` | **Excellent** | **High** | **All configurations, best price/performance** |
| **3 - LIMITED** | A10 | 24 GB | `BM.GPU.A10.4` | **Restricted** | Standard | Config 3 & 4 only (Nano models) |

### Configuration Requirements by GPU Type

| Configuration | Minimum GPUs | **RECOMMENDED SHAPE** | GPU Memory Required |
|---------------|--------------|----------------------|---------------------|
| **Config 1: Full Blueprint (70B LLM)** | 8 | `BM.GPU.H100.8` or `BM.GPU.A100-v2.8` | 640GB (8x80GB) |
| **Config 2: Text-Only (70B LLM)** | 4 | `BM.GPU.H100.8` or `BM.GPU.A100-v2.8` | 320GB (4x80GB) |
| **Config 3: Nano 9B + GPU Milvus** | 8 | `BM.GPU.H100.8` or `BM.GPU.A100-v2.8` | 192GB (8x24GB) |
| **Config 4: VLM Full (Nano models)** | 8 | `BM.GPU.H100.8` or `BM.GPU.A100-v2.8` | 192GB (8x24GB) |

### Model Memory Requirements

> **Critical:** Model size determines minimum GPU memory requirements.

| Model | Parameters | Memory Required (FP16/BF16) | Minimum GPU Memory |
|-------|------------|-----------------------------|--------------------|
| **Llama 3.1 70B** | 70B | ~140GB (2 GPUs) | 80GB per GPU |
| **Nemotron Super 49B** | 49B | ~98GB (2 GPUs) | 80GB per GPU |
| **Nemotron Nano 9B** | 9B | ~18GB | 24GB |
| **Nemotron Nano VL 8B** | 8B | ~16GB | 24GB |
| **Embedding Models** | 1B | ~2GB | Any GPU |

---

### Key Takeaways - GPU Selection

**H100 / A100 (Recommended):**
- **H100**: Best performance, fastest inference, supports all models and configurations
- **A100**: Excellent all-around choice, 80GB memory supports all RAG Blueprint configurations
- **Universal compatibility** - works with ALL 4 configurations
- **Production ready** - proven performance and reliability

**A10 (Limited Use Cases):**
- Only supports Config 3 & 4 with Nano models (9B/8B)
- Cannot run Config 1 or Config 2 (70B models require 80GB GPU memory)
- Suitable for budget-constrained deployments using smaller models

**Bottom Line:** For this workshop, use `BM.GPU.A100-v2.8` or `BM.GPU.H100.8` for the best experience.

---

## Security Best Practices

1. **Network Security**:
   - Use private subnets for worker nodes
   - Restrict LoadBalancer source ranges
   - Enable Network Security Groups

2. **Secrets Management**:
   - Store NGC API key in Kubernetes secrets
   - Rotate secrets regularly
   - Use OCI Vault for sensitive data

3. **Access Control**:
   - Implement RBAC for cluster access
   - Use namespace isolation
   - Enable audit logging

4. **Data Protection**:
   - Encrypt persistent volumes
   - Enable TLS for LoadBalancer services
   - Backup Milvus vector database regularly

---

## Performance Tips

1. **Model Optimization**:
   - Use Config 2 (Text-Only) for 50% cost savings
   - Use Config 3 (Nano) for lower latency
   - Enable GPU Milvus for faster vector search

2. **Scaling**:
   - Scale frontend for more concurrent users
   - Scale RAG server for higher query throughput
   - Use HPA (Horizontal Pod Autoscaler) for automatic scaling

3. **Resource Management**:
   - Set appropriate resource requests/limits
   - Monitor GPU utilization with DCGM
   - Use node affinity for optimal placement

---

## Additional Resources

- **NVIDIA RAG Blueprint**: [https://github.com/NVIDIA-AI-Blueprints/rag](https://github.com/NVIDIA-AI-Blueprints/rag)
- **NVIDIA NIM Documentation**: [https://docs.nvidia.com/nim/](https://docs.nvidia.com/nim/)
- **OKE Documentation**: [https://docs.oracle.com/en-us/iaas/Content/ContEng/home.htm](https://docs.oracle.com/en-us/iaas/Content/ContEng/home.htm)
- **Milvus Documentation**: [https://milvus.io/docs](https://milvus.io/docs)
- **NGC Catalog**: [https://catalog.ngc.nvidia.com/](https://catalog.ngc.nvidia.com/)

---

## Next Steps

Now that you have RAG deployed on OKE, explore these advanced topics:

1. **Custom Models**: Replace default LLM with your fine-tuned models
2. **Multi-Tenancy**: Deploy multiple RAG instances with namespace isolation
3. **Production Hardening**: Implement monitoring, logging, and alerting
4. **Performance Tuning**: Optimize chunk sizes and retrieval parameters
5. **Integration**: Connect RAG to your enterprise applications via API

---

## Cleanup

To remove the RAG deployment and free resources:

```bash
# Uninstall RAG Helm chart
helm uninstall rag --namespace default

# Delete GPU operator (if installed)
helm uninstall gpu-operator --namespace gpu-operator
kubectl delete namespace gpu-operator

# Delete OKE node pool (will take 10-15 minutes)
oci ce node-pool delete --node-pool-id <NODE_POOL_OCID> --force

# Delete OKE cluster (will take 10-15 minutes)
oci ce cluster delete --cluster-id <CLUSTER_OCID> --force

# Delete VCN and networking (after cluster deletion completes)
oci network vcn delete --vcn-id <VCN_OCID> --force
```

---

## Congratulations!

You have successfully deployed the NVIDIA RAG Pipeline Blueprint on OKE!

**What you've accomplished:**
- Set up GPU-enabled OKE cluster
- Deployed production-ready RAG pipeline
- Integrated LLM, embeddings, and vector database
- Created document Q&A system with citations
- Configured LoadBalancer for external access

**Your RAG system can now:**
- Process and ingest documents (PDFs, text, images)
- Generate embeddings and store in Milvus
- Answer questions with source citations
- Handle multi-modal content (depending on configuration)
- Scale to handle enterprise workloads

**Happy Building with RAG!**

