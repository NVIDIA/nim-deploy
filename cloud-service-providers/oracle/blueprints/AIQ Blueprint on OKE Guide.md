# NVIDIA AIQ Blueprint on Oracle Kubernetes Engine (OKE)

This guide provides step-by-step instructions for deploying the NVIDIA AIQ (AI-Q Research Assistant) Blueprint on Oracle Cloud Infrastructure (OCI) using Oracle Kubernetes Engine (OKE) and GPU instances.

> *For the most up-to-date information, licensing, and terms of use, please refer to the [NVIDIA AIQ Blueprint](https://github.com/NVIDIA-AI-Blueprints/aiq).*

## Overview

The NVIDIA AIQ Blueprint deploys an AI-powered research assistant that combines agentic workflows with Retrieval Augmented Generation (RAG) capabilities. AIQ enables users to conduct research, analyze documents, and generate insights using advanced language models.

**Important**: The AIQ Blueprint requires the RAG Blueprint to be deployed first. AIQ builds on top of RAG's document ingestion, embedding, and retrieval capabilities.

### Key Features

- Agentic workflows with AI-powered research assistant that can plan and execute complex tasks
- RAG integration leveraging the RAG Blueprint for document ingestion and retrieval
- Multi-model support using separate LLMs for instruction-following and reasoning tasks
- Interactive research assistant web interface for conducting research
- Document analysis with context-aware responses

### Architecture Components

| Component | Purpose |
|-----------|---------|
| AIQ Backend | Agentic workflow orchestration |
| AIQ Frontend | Research assistant web interface |
| Instruct LLM | Llama 3.3 70B for instruction-following (Full AIQ only) |
| RAG LLM | Nemotron Super 49B for reasoning (from RAG Blueprint) |
| RAG Server | Document retrieval and Q&A |
| Milvus | Vector database for embeddings |

## Prerequisites

Before starting the deployment process, ensure you have the following:

- **Oracle Cloud Infrastructure (OCI) Account** with access to GPU instances
- **NVIDIA NGC Account** for an **NGC API Key** to pull container images. Sign up at [ngc.nvidia.com](https://ngc.nvidia.com/setup/api-key)
- **OCI CLI** installed and configured/authenticated
- **kubectl** Kubernetes command-line tool
- **Helm 3.x** package manager for Kubernetes

### IAM Policy Requirements

The deployment requires specific OCI Identity and Access Management (IAM) permissions. Ensure your user/group has the following permissions (either directly or via dynamic groups):

```
Allow group <GROUP_NAME> to manage instance-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to manage cluster-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to manage virtual-network-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to use subnets in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to manage secret-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to use instance-configurations in compartment <COMPARTMENT_NAME>
```

## Hardware Requirements

| Configuration | H100 80GB | A100 80GB |
|---------------|-----------|-----------|
| Full RAG + Full AIQ | 10 | 13 |
| Full RAG + Shared LLM AIQ | 8 | 9 |
| Text Ingestion RAG + Full AIQ | 6 | 9 |
| Text Ingestion RAG + Shared LLM AIQ | 4 | 5 |

> **Note**: Nemotron Super 49B requires 1 GPU on H100 but 2 GPUs on A100 due to FP8 vs FP16 quantization.

**Additional Requirements:**
- **Boot Volume**: Minimum 500GB

---

## Infrastructure Setup

This section covers the steps to prepare your OCI infrastructure for running the AIQ Blueprint.

### Console Quick Create (Recommended)

The fastest way - auto-provisions networking.

1. Go to **OCI Console** → **Developer Services** → **Kubernetes Clusters (OKE)**
2. Click **Create cluster** → Select **Quick create** → **Submit**
3. Configure:
   - Name: `gpu-cluster`
   - Kubernetes API endpoint: **Public endpoint**
   - Shape: Select GPU shape based on [Hardware Requirements](#hardware-requirements)
   - Nodes: `1`
   - Boot volume: `500` GB
4. Click **Create cluster** and wait 10-15 min
5. Configure kubectl:
```bash
export CLUSTER_ID="<cluster-ocid-from-console>"
export REGION="<your-region>"
oci ce cluster create-kubeconfig --cluster-id $CLUSTER_ID --region $REGION \
  --file $HOME/.kube/config --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT
```

> **Need CLI/scripted deployment?** See [Appendix: CLI Deployment](#appendix-cli-deployment) at the bottom.

---

### Pre-Deployment Setup

> **Already have a cluster?** Start here. Created one above? Continue here.

#### 1. Verify Storage Size

Check that your node's storage matches your boot volume size:

```bash
kubectl describe nodes | grep ephemeral-storage | head -1
```

If you specified 500GB boot volume, you should see ~`512628992Ki` (~489GB). If you see ~`37206272Ki` (~35GB), the volume needs expanding - continue to step 2. Otherwise, skip to step 3.

#### 2. Expand Boot Volume (if needed)

**Option A: Via kubectl (no SSH required)**

```bash
# Get node name
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# Expand filesystem
kubectl run growfs --rm -it --restart=Never --privileged \
  --overrides='{"spec":{"hostPID":true,"nodeName":"'$NODE_NAME'"}}' \
  --image=docker.io/library/oraclelinux:8 -- nsenter -t 1 -m -u -i -n /usr/libexec/oci-growfs -y

# Restart kubelet to pick up new size
kubectl run restart-kubelet --rm -it --restart=Never --privileged \
  --overrides='{"spec":{"hostPID":true,"nodeName":"'$NODE_NAME'"}}' \
  --image=docker.io/library/oraclelinux:8 -- nsenter -t 1 -m -u -i -n systemctl restart kubelet

# Verify (should now show ~512628992Ki for 500GB)
sleep 10 && kubectl describe nodes | grep ephemeral-storage | head -1
```

**Option B: Via SSH (if you have node access)**

```bash
sudo /usr/libexec/oci-growfs -y
sudo systemctl restart kubelet
```

#### 3. Setup Cluster

```bash
# Remove GPU taints
kubectl taint nodes --all nvidia.com/gpu:NoSchedule- 2>/dev/null || true

# Verify GPU resources
kubectl describe nodes | grep -A5 "Allocatable:" | grep gpu

# Add NVIDIA Blueprint Helm repository
export NGC_API_KEY="<your-ngc-api-key>"
helm repo add nvidia-blueprint https://helm.ngc.nvidia.com/nvidia/blueprint \
  --username='$oauthtoken' --password=$NGC_API_KEY
helm repo update
```

Expected Output:
```
node/10.0.10.xx untainted
  nvidia.com/gpu:             8
"nvidia-blueprint" has been added to your repositories
Update Complete. Happy Helming!
```

---

## Deploy the RAG Blueprint

AIQ requires the RAG Blueprint to be deployed first. Choose one of the following RAG configurations:

### Option A: Full RAG Blueprint (8 GPUs H100 / 9 GPUs A100)

Deploy the complete RAG pipeline with all components:

```bash
helm install rag nvidia-blueprint/nvidia-blueprint-rag \
  --namespace rag --create-namespace \
  --set imagePullSecret.password=$NGC_API_KEY \
  --set ngcApiSecret.password=$NGC_API_KEY \
  --set nv-ingest.milvus.image.all.repository=docker.io/milvusdb/milvus \
  --set nv-ingest.milvus.image.tools.repository=docker.io/milvusdb/milvus-config-tool \
  --set nv-ingest.milvus.minio.image.repository=docker.io/minio/minio \
  --set frontend.service.type=LoadBalancer
```

Expected Output:
```
NAME: rag
LAST DEPLOYED: Thu Jan 30 12:15:00 2026
NAMESPACE: rag
STATUS: deployed
REVISION: 1
```

> **Note**: The `docker.io/` prefix is required on OKE because CRI-O enforces fully qualified image names.

**For A100 (9 GPUs)** - add LLM GPU override:

```bash
  --set nim-llm.resources.limits."nvidia\.com/gpu"=2 \
  --set nim-llm.resources.requests."nvidia\.com/gpu"=2
```

---

### Option B: Text Ingestion Only RAG (4 GPUs H100 / 5 GPUs A100)

For smaller clusters, deploy with only LLM, Embed, Rerank, and Page Elements:

```bash
helm install rag nvidia-blueprint/nvidia-blueprint-rag \
  --namespace rag --create-namespace \
  --set imagePullSecret.password=$NGC_API_KEY \
  --set ngcApiSecret.password=$NGC_API_KEY \
  --set nv-ingest.milvus.image.all.repository=docker.io/milvusdb/milvus \
  --set nv-ingest.milvus.image.tools.repository=docker.io/milvusdb/milvus-config-tool \
  --set nv-ingest.milvus.minio.image.repository=docker.io/minio/minio \
  --set nv-ingest.nemoretriever-graphic-elements-v1.deployed=false \
  --set nv-ingest.nemoretriever-table-structure-v1.deployed=false \
  --set nv-ingest.paddleocr-nim.deployed=false \
  --set frontend.service.type=LoadBalancer
```

Expected Output:
```
NAME: rag
LAST DEPLOYED: Thu Jan 30 12:15:00 2026
NAMESPACE: rag
STATUS: deployed
REVISION: 1
```

**For A100 (5 GPUs)** - add LLM GPU override:

```bash
  --set nim-llm.resources.limits."nvidia\.com/gpu"=2 \
  --set nim-llm.resources.requests."nvidia\.com/gpu"=2
```

---

### Verify RAG Deployment

Wait for all pods to be ready (10-15 minutes for LLM model download):

```bash
kubectl get pods -n rag -w
```

Expected Output (after 10-15 minutes):
```
NAME                                           READY   STATUS    RESTARTS   AGE
rag-nim-llm-0                                  1/1     Running   0          15m
milvus-standalone-7d8bb68445-xxxxx             1/1     Running   0          15m
rag-frontend-7b9c8d7f56-xxxxx                  1/1     Running   0          15m
rag-server-xxxxx                               1/1     Running   0          15m
ingestor-server-xxxxx                          1/1     Running   0          15m
```

Verify RAG is accessible:

```bash
echo "RAG Playground: http://$(kubectl get svc rag-frontend -n rag -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):3000"
```

Expected Output:
```
RAG Playground: http://129.xxx.xxx.xxx:3000
```

---

## Deploy the AIQ Blueprint

AIQ is deployed in its own `aiq` namespace to avoid Helm secret conflicts with RAG. It connects to RAG services via cross-namespace DNS.

Choose one of the following AIQ configurations:

### Configuration 1: Full AIQ Blueprint (adds 2 GPUs H100 / 4 GPUs A100)

Deploys AIQ with its own Instruct LLM (Llama 3.3 70B Instruct) for instruction-following tasks.

**Additional GPUs Required:**
| Component | H100 | A100 |
|-----------|------|------|
| Instruct LLM (Llama 3.3 70B) | 2 | 4 |

```bash
helm install aiq nvidia-blueprint/aiq-aira \
  --namespace aiq --create-namespace \
  --set imagePullSecret.password=$NGC_API_KEY \
  --set imagePullSecret.name=aiq-ngc-secret \
  --set ngcApiSecret.password=$NGC_API_KEY \
  --set ngcApiSecret.name=aiq-ngc-api \
  --set nim-llm.model.ngcAPIKey=$NGC_API_KEY \
  --set frontend.service.type=LoadBalancer \
  --set phoenix.enabled=false
```

Expected Output:
```
NAME: aiq
LAST DEPLOYED: Thu Jan 30 12:30:00 2026
NAMESPACE: aiq
STATUS: deployed
REVISION: 1
```

> **Note**: The secret names (`aiq-ngc-secret`, `aiq-ngc-api`) are changed to avoid conflicts with the nim-llm subchart.

**Expected AIQ Pods (in `aiq` namespace):**
| Pod Name Pattern | Description |
|-----------------|-------------|
| `aiq-aira-backend-*` | AIQ backend service |
| `aiq-aira-frontend-*` | AIQ web interface |
| `aiq-nim-llm-0` | Llama 3.3 70B Instruct LLM (2 GPUs H100 / 4 GPUs A100) |

---

### Configuration 2: Shared LLM AIQ (adds 0 GPUs)

Uses the existing RAG LLM (Nemotron Super 49B) for both reasoning AND instruction-following. No additional LLM deployment required.

**Additional GPUs Required:** None (uses existing RAG LLM)

```bash
helm install aiq nvidia-blueprint/aiq-aira \
  --namespace aiq --create-namespace \
  --set imagePullSecret.password=$NGC_API_KEY \
  --set ngcApiSecret.password=$NGC_API_KEY \
  --set nim-llm.enabled=false \
  --set backendEnvVars.INSTRUCT_BASE_URL="http://nim-llm.rag.svc.cluster.local:8000/v1" \
  --set backendEnvVars.INSTRUCT_MODEL_NAME="nvidia/llama-3.3-nemotron-super-49b-v1.5" \
  --set frontend.service.type=LoadBalancer \
  --set phoenix.enabled=false
```

Expected Output:
```
NAME: aiq
LAST DEPLOYED: Thu Jan 30 12:30:00 2026
NAMESPACE: aiq
STATUS: deployed
REVISION: 1
```

**Expected AIQ Pods (in `aiq` namespace):**
| Pod Name Pattern | Description |
|-----------------|-------------|
| `aiq-aira-backend-*` | AIQ backend service |
| `aiq-aira-frontend-*` | AIQ web interface |

> **Note**: No LLM pod in `aiq` namespace - using RAG's `rag-nim-llm-0` for both tasks.

---

## Verification

### Monitor Deployment Status

Wait for pods to be ready (5-10 minutes, or 10-15 minutes if using Full AIQ with Instruct LLM):

```bash
kubectl get pods -n aiq -w
```

Expected Output (Config 1 - Full AIQ):
```
NAME                                READY   STATUS    RESTARTS   AGE
aiq-aira-backend-xxxxx              1/1     Running   0          10m
aiq-aira-frontend-xxxxx             1/1     Running   0          10m
aiq-nim-llm-0                       1/1     Running   0          10m
```

Expected Output (Config 2 - Shared LLM):
```
NAME                                READY   STATUS    RESTARTS   AGE
aiq-aira-backend-xxxxx              1/1     Running   0          5m
aiq-aira-frontend-xxxxx             1/1     Running   0          5m
```

### Get AIQ Frontend URL

```bash
echo "AIQ Research Assistant: http://$(kubectl get svc aiq-aira-frontend -n aiq -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):3000"
```

Expected Output:
```
AIQ Research Assistant: http://129.xxx.xxx.xxx:3000
```

### Verify RAG Pods Running

```bash
kubectl get pods -n rag
```

Expected Output:
```
NAME                                           READY   STATUS    RESTARTS   AGE
rag-nim-llm-0                                  1/1     Running   0          30m
milvus-standalone-7d8bb68445-xxxxx             1/1     Running   0          30m
rag-frontend-7b9c8d7f56-xxxxx                  1/1     Running   0          30m
rag-server-xxxxx                               1/1     Running   0          30m
```

### Accessing the Applications

| Application | Description | URL |
|-------------|-------------|-----|
| AIQ Research Assistant | Agentic research interface | `http://<AIQ-FRONTEND-IP>:3000` |
| RAG Playground | Document upload and Q&A | `http://<RAG-FRONTEND-IP>:3000` |

---

## Troubleshooting

### AIQ Pods Not Starting

```bash
# Check pod events
kubectl describe pod -n aiq -l app=aira-backend
```

```bash
# Check logs
kubectl logs -n aiq -l app=aira-backend
```

### AIQ Cannot Connect to RAG LLM

```bash
# Verify RAG LLM is running
kubectl get pods -n rag | grep nim-llm
```

Expected Output:
```
rag-nim-llm-0   1/1     Running   0   45m
```

```bash
# Test LLM endpoint from AIQ pod
kubectl exec -n aiq -it deploy/aiq-aira-backend -- curl http://nim-llm.rag.svc.cluster.local:8000/v1/health/ready
```

Expected Output:
```
{"status":"ready"}
```

### AIQ Cannot Connect to RAG Server

```bash
# Verify RAG server is running
kubectl get pods -n rag | grep rag-server
```

Expected Output:
```
rag-server-xxxxx   1/1     Running   0   45m
```

```bash
# Check RAG server logs
kubectl logs -n rag -l app=rag-server --tail=20
```

### Instruct LLM Not Starting (Config 1 Only)

```bash
# Check pod status
kubectl describe pod -n aiq aiq-nim-llm-0
```

```bash
# Check logs for model download progress
kubectl logs -n aiq aiq-nim-llm-0 --tail=20
```

Expected Output (downloading):
```
Downloading model files...
Progress: 45%
```

### NGC Authentication Errors (ImagePullBackOff)

```bash
# Verify API key is set
echo $NGC_API_KEY
```

```bash
# Check secrets exist in both namespaces
kubectl get secret -n rag | grep ngc
kubectl get secret -n aiq | grep ngc
```

Expected Output:
```
ngc-api          Opaque           1      15m
ngc-secret       kubernetes.io/dockerconfigjson   1      15m
```

---

## Cleanup

### Remove AIQ Blueprint

```bash
# Delete Helm release
helm uninstall aiq --namespace aiq

# Wait for pods to terminate
echo "Waiting for pods to terminate..."
kubectl wait --for=delete pod -n aiq --all --timeout=120s 2>/dev/null || true

# Delete namespace
kubectl delete namespace aiq
```

Expected Output:
```
release "aiq" uninstalled
Waiting for pods to terminate...
namespace "aiq" deleted
```

### Remove RAG Blueprint

```bash
# Delete Helm release
helm uninstall rag --namespace rag

# Wait for pods to terminate
echo "Waiting for pods to terminate..."
kubectl wait --for=delete pod -n rag --all --timeout=120s 2>/dev/null || true

# Delete all persistent volume claims
kubectl delete pvc -n rag --all

# Wait for volumes to detach from nodes
echo "Waiting 60s for OCI block volumes to detach..."
sleep 60

# Delete namespace
kubectl delete namespace rag

# Verify cleanup
kubectl get all -n rag 2>/dev/null && echo "WARNING: Some resources remain" || echo "Cleanup complete"
```

Expected Output:
```
release "rag" uninstalled
Waiting for pods to terminate...
persistentvolumeclaim "data-milvus-standalone-0" deleted
persistentvolumeclaim "rag-minio" deleted
Waiting 60s for OCI block volumes to detach...
namespace "rag" deleted
Cleanup complete
```

---

## Deployment Checklist

Ensure the following are complete:

- [ ] OKE cluster is active and accessible
- [ ] GPU node pool is ready and healthy (see [Hardware Requirements](#hardware-requirements))
- [ ] NAT Gateway configured for outbound internet access
- [ ] NGC API key exported (`export NGC_API_KEY=...`)
- [ ] Helm repo added (`helm repo list` shows nvidia-blueprint)
- [ ] RAG Blueprint deployed and all pods Running (`kubectl get pods -n rag`)
- [ ] RAG Frontend LoadBalancer has external IP
- [ ] AIQ Blueprint deployed and all pods Running (`kubectl get pods -n aiq`)
- [ ] AIQ Frontend LoadBalancer has external IP
- [ ] AIQ Research Assistant accessible at `http://<EXTERNAL-IP>:3000`

---

## Appendix: CLI Deployment

Use this for automation or scripted deployments. 5 blocks: set variables → copy-paste each block → wait for completion → next block.

### 1. Set Variables (EDIT THESE)

```bash
export COMPARTMENT_ID="<your-compartment-ocid>"
export REGION="<your-region>"
export CLUSTER_NAME="gpu-cluster"
export VCN_NAME="gpu-vcn"
export NODE_SHAPE="<gpu-shape>"  # See Hardware Requirements (e.g., BM.GPU.H100.8, BM.GPU.A100-v2.8)
export NODE_COUNT=1
export CAPACITY_RESERVATION_ID=""  # Optional: ocid1.capacityreservation... or leave empty for on-demand

K8S_VERSION=$(oci ce cluster-options get --cluster-option-id all --region $REGION \
  --query 'data."kubernetes-versions" | [-1]' --raw-output)
echo "K8s: $K8S_VERSION | Shape: $NODE_SHAPE | Region: $REGION"
```

### 2. Create Network Infrastructure

```bash
# Create VCN
VCN_ID=$(oci network vcn create \
  --compartment-id $COMPARTMENT_ID \
  --region $REGION \
  --display-name "$VCN_NAME" \
  --cidr-blocks '["10.0.0.0/16"]' \
  --query 'data.id' --raw-output)

# Create Internet Gateway (for public subnets)
IGW_ID=$(oci network internet-gateway create \
  --compartment-id $COMPARTMENT_ID \
  --region $REGION \
  --vcn-id $VCN_ID \
  --display-name "${VCN_NAME}-igw" \
  --is-enabled true \
  --query 'data.id' --raw-output)

# Create NAT Gateway (for private subnet outbound)
NAT_ID=$(oci network nat-gateway create \
  --compartment-id $COMPARTMENT_ID \
  --region $REGION \
  --vcn-id $VCN_ID \
  --display-name "${VCN_NAME}-nat" \
  --query 'data.id' --raw-output)

# Create public route table (internet access)
PUBLIC_RT_ID=$(oci network route-table create \
  --compartment-id $COMPARTMENT_ID \
  --region $REGION \
  --vcn-id $VCN_ID \
  --display-name "${VCN_NAME}-public-rt" \
  --route-rules '[{"destination":"0.0.0.0/0","networkEntityId":"'$IGW_ID'"}]' \
  --query 'data.id' --raw-output)

# Create private route table (NAT for outbound)
PRIVATE_RT_ID=$(oci network route-table create \
  --compartment-id $COMPARTMENT_ID \
  --region $REGION \
  --vcn-id $VCN_ID \
  --display-name "${VCN_NAME}-private-rt" \
  --route-rules '[{"destination":"0.0.0.0/0","networkEntityId":"'$NAT_ID'"}]' \
  --query 'data.id' --raw-output)

# Create control plane subnet (public)
CP_SUBNET_ID=$(oci network subnet create \
  --compartment-id $COMPARTMENT_ID \
  --region $REGION \
  --vcn-id $VCN_ID \
  --display-name "${VCN_NAME}-control-plane" \
  --cidr-block "10.0.0.0/28" \
  --route-table-id $PUBLIC_RT_ID \
  --query 'data.id' --raw-output)

# Create worker subnet (private)
WORKER_SUBNET_ID=$(oci network subnet create \
  --compartment-id $COMPARTMENT_ID \
  --region $REGION \
  --vcn-id $VCN_ID \
  --display-name "${VCN_NAME}-workers" \
  --cidr-block "10.0.10.0/24" \
  --route-table-id $PRIVATE_RT_ID \
  --prohibit-public-ip-on-vnic true \
  --query 'data.id' --raw-output)

# Create load balancer subnet (public)
LB_SUBNET_ID=$(oci network subnet create \
  --compartment-id $COMPARTMENT_ID \
  --region $REGION \
  --vcn-id $VCN_ID \
  --display-name "${VCN_NAME}-loadbalancers" \
  --cidr-block "10.0.20.0/24" \
  --route-table-id $PUBLIC_RT_ID \
  --query 'data.id' --raw-output)

# Update security list for OKE traffic
DEFAULT_SL_ID=$(oci network security-list list \
  --compartment-id $COMPARTMENT_ID \
  --region $REGION \
  --vcn-id $VCN_ID \
  --query "data[0].id" --raw-output)

oci network security-list update \
  --security-list-id $DEFAULT_SL_ID \
  --region $REGION \
  --force \
  --ingress-security-rules '[
    {"source":"10.0.0.0/16","protocol":"all","isStateless":false},
    {"source":"0.0.0.0/0","protocol":"6","tcpOptions":{"destinationPortRange":{"min":6443,"max":6443}},"isStateless":false},
    {"source":"0.0.0.0/0","protocol":"1","isStateless":false}
  ]' \
  --egress-security-rules '[{"destination":"0.0.0.0/0","protocol":"all","isStateless":false}]' \
  >/dev/null

echo "VCN=$VCN_ID"
echo "Worker=$WORKER_SUBNET_ID"
echo "LB=$LB_SUBNET_ID"
```

### 3. Create OKE Cluster (wait 5-10 min for ACTIVE)

```bash
oci ce cluster create \
  --compartment-id $COMPARTMENT_ID \
  --region $REGION \
  --name "$CLUSTER_NAME" \
  --kubernetes-version "$K8S_VERSION" \
  --vcn-id $VCN_ID \
  --endpoint-subnet-id $CP_SUBNET_ID \
  --service-lb-subnet-ids '["'$LB_SUBNET_ID'"]' \
  --endpoint-public-ip-enabled true \
  --cluster-pod-network-options '[{"cniType":"OCI_VCN_IP_NATIVE"}]' \
  --type ENHANCED_CLUSTER

# Wait then get cluster ID
sleep 30
CLUSTER_ID=$(oci ce cluster list \
  --compartment-id $COMPARTMENT_ID \
  --region $REGION \
  --query "data[?name=='$CLUSTER_NAME' && \"lifecycle-state\"!='DELETED'].id | [0]" \
  --raw-output)
echo "CLUSTER_ID=$CLUSTER_ID"

# Check status (repeat until ACTIVE)
oci ce cluster get --cluster-id $CLUSTER_ID --region $REGION \
  --query 'data."lifecycle-state"' --raw-output
```

### 4. Create GPU Node Pool (wait 10-15 min for node ACTIVE)

```bash
# Get GPU image for this K8s version
K8S_SHORT=$(echo $K8S_VERSION | sed 's/v//')
IMAGE_ID=$(oci ce node-pool-options get \
  --node-pool-option-id all \
  --compartment-id $COMPARTMENT_ID \
  --region $REGION \
  --query "data.sources[?contains(\"source-name\",'GPU') && contains(\"source-name\",'$K8S_SHORT')].\"image-id\" | [0]" \
  --raw-output)

# Get placement config (with or without capacity reservation)
if [ -n "$CAPACITY_RESERVATION_ID" ]; then
  AD=$(oci compute capacity-reservation get \
    --capacity-reservation-id $CAPACITY_RESERVATION_ID \
    --region $REGION \
    --query 'data."availability-domain"' --raw-output)
  PLACEMENT='[{"availabilityDomain":"'$AD'","capacityReservationId":"'$CAPACITY_RESERVATION_ID'","subnetId":"'$WORKER_SUBNET_ID'"}]'
  echo "Using Capacity Reservation ($AD)"
else
  AD=$(oci iam availability-domain list \
    --compartment-id $COMPARTMENT_ID \
    --region $REGION \
    --query 'data[0].name' --raw-output)
  PLACEMENT='[{"availabilityDomain":"'$AD'","subnetId":"'$WORKER_SUBNET_ID'"}]'
  echo "Using On-Demand ($AD)"
fi

# Create node pool
oci ce node-pool create \
  --cluster-id $CLUSTER_ID \
  --compartment-id $COMPARTMENT_ID \
  --region $REGION \
  --name "gpu-node-pool" \
  --kubernetes-version "$K8S_VERSION" \
  --node-shape "$NODE_SHAPE" \
  --size $NODE_COUNT \
  --placement-configs "$PLACEMENT" \
  --node-source-details '{"sourceType":"IMAGE","imageId":"'$IMAGE_ID'","bootVolumeSizeInGBs":500}' \
  --pod-subnet-ids '["'$WORKER_SUBNET_ID'"]'

# Get node pool ID
sleep 10
NODE_POOL_ID=$(oci ce node-pool list \
  --cluster-id $CLUSTER_ID \
  --compartment-id $COMPARTMENT_ID \
  --region $REGION \
  --query 'data[0].id' --raw-output)
echo "NODE_POOL_ID=$NODE_POOL_ID"

# Check node status (repeat until ACTIVE)
oci ce node-pool get --node-pool-id $NODE_POOL_ID --region $REGION \
  --query 'data.nodes[0].{"state":"lifecycle-state","details":"lifecycle-details"}' 2>/dev/null
```

### 5. Configure kubectl

```bash
oci ce cluster create-kubeconfig --cluster-id $CLUSTER_ID --region $REGION \
  --file $HOME/.kube/config --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT
```

Then continue with [Pre-Deployment Setup](#pre-deployment-setup).
