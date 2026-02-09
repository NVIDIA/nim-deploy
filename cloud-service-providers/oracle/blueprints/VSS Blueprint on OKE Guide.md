# NVIDIA VSS Blueprint on Oracle Kubernetes Engine (OKE)

This guide provides step-by-step instructions for deploying the NVIDIA VSS (Video Search and Summarization) Blueprint on Oracle Cloud Infrastructure (OCI) using Oracle Kubernetes Engine (OKE) and GPU instances.

> *For the most up-to-date information, licensing, and terms of use, please refer to the [NVIDIA VSS Blueprint](https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization).*

## Overview

The NVIDIA Video Search and Summarization Blueprint enables intelligent video analysis using AI. It combines Vision Language Models (VLM) with Large Language Models (LLM) to understand video content, extract insights, and enable natural language search across video libraries.

### Key Features

- Video content understanding via Vision Language Model (VLM)
- Natural language search across video content
- Automatic video summarization
- Multi-modal retrieval (text, visual, semantic)
- Integration with multiple vector and graph databases
- Reranking for improved search accuracy
- OpenAI-compatible APIs

### Architecture Components

| Component | Purpose |
|-----------|---------|
| VSS Engine | Main application - video processing and search UI |
| NIM LLM | Llama 3.1 70B - text generation and summarization |
| NeMo Embedding | Text embeddings for semantic search |
| NeMo Rerank | Rerank search results for accuracy |
| Milvus | Vector database for embeddings |
| Neo4j | Graph database for relationships |
| Elasticsearch | Full-text search |
| ArangoDB | Document store |
| MinIO | Object storage for videos |
| etcd | Distributed KV store |

## Prerequisites

Before starting the deployment process, ensure you have the following:

- **Oracle Cloud Infrastructure (OCI) Account** with access to GPU instances
- **NVIDIA NGC Account** for an **NGC API Key** to pull container images. Sign up at [ngc.nvidia.com](https://ngc.nvidia.com/setup/api-key)
- **HuggingFace Account** with access to `nvidia/Cosmos-Reason2-8B` model:
  1. Go to https://huggingface.co/nvidia/Cosmos-Reason2-8B
  2. **Click "Agree and access repository"** to accept the license (required)
  3. Get your token from https://huggingface.co/settings/tokens (create one with "Read" access)
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
| Full Blueprint | 8 | 9 |

**GPU Breakdown (H100):**

| Component | H100 GPUs | A100 GPUs |
|-----------|-----------|-----------|
| VSS VLM | 2 | 2 |
| LLM (Llama 3.1 70B) | 4 | 5 |
| Embedding | 1 | 1 |
| Rerank | 1 | 1 |
| **Total** | **8** | **9** |

> **Note**: A100 requires 9 GPUs (5 for LLM vs 4 on H100) due to lower memory bandwidth.

**Additional Requirements:**
- **Boot Volume**: Minimum 500GB
- **Block Storage**: ~350GB for model caches (auto-provisioned via PVCs)

---

## Infrastructure Setup

This section covers the steps to prepare your OCI infrastructure for running the VSS Blueprint.

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

## Deployment

Deploy the VSS Blueprint:

```bash
export HF_TOKEN="<your-huggingface-token>"

helm install vss nvidia-blueprint/nvidia-blueprint-vss \
  --namespace vss --create-namespace \
  --set imagePullSecret.password=$NGC_API_KEY \
  --set ngcApiSecret.password=$NGC_API_KEY \
  --set vss.env.HF_TOKEN=$HF_TOKEN \
  --set vss.env.HUGGING_FACE_HUB_TOKEN=$HF_TOKEN \
  --set arango-db.image.repository=docker.io/arangodb \
  --set elasticsearch.image.repository=docker.elastic.co/elasticsearch/elasticsearch \
  --set elasticsearch.image.tag=8.17.0 \
  --set milvus.image.repository=docker.io/milvusdb/milvus \
  --set milvus-minio.image.repository=docker.io/minio/minio \
  --set minio.image.repository=docker.io/minio/minio \
  --set neo4j.image.repository=docker.io/library/neo4j \
  --set vss.initContainers.checkLlmUp.image.repository=docker.io/curlimages/curl \
  --set nemo-rerank.podSecurityContext.fsGroup=1000 \
  --set nim-llm.persistence.size=200Gi \
  --set vss.service.type=LoadBalancer
```

Expected Output:
```
NAME: vss
LAST DEPLOYED: Fri Jan 31 10:00:00 2026
NAMESPACE: vss
STATUS: deployed
REVISION: 1
```

> **Note**: The `docker.io/` prefix is required on OKE because CRI-O enforces fully qualified image names.

---

## Verification

### Monitor Deployment Status

Wait for pods to be ready (15-20 minutes for LLM model download):

```bash
kubectl get pods -n vss -w
```

Expected Output (initial state):
```
NAME                                                      READY   STATUS              RESTARTS   AGE
arango-db-arango-db-deployment-xxxxx                      0/1     ContainerCreating   0          2m
elasticsearch-elasticsearch-deployment-xxxxx              0/1     ContainerCreating   0          2m
nim-llm-0                                                 0/1     Init:0/1            0          2m
vss-vss-deployment-xxxxx                                  0/1     Init:0/3            0          2m
```

Expected Output (after 15-20 minutes):
```
NAME                                                      READY   STATUS    RESTARTS   AGE
arango-db-arango-db-deployment-xxxxx                      1/1     Running   0          20m
elasticsearch-elasticsearch-deployment-xxxxx              1/1     Running   0          20m
etcd-etcd-deployment-xxxxx                                1/1     Running   0          20m
milvus-milvus-deployment-xxxxx                            1/1     Running   0          20m
milvus-minio-milvus-minio-deployment-xxxxx                1/1     Running   0          20m
minio-minio-deployment-xxxxx                              1/1     Running   0          20m
nemo-embedding-embedding-deployment-xxxxx                 1/1     Running   0          20m
nemo-rerank-ranking-deployment-xxxxx                      1/1     Running   0          20m
neo4j-neo4j-deployment-xxxxx                              1/1     Running   0          20m
nim-llm-0                                                 1/1     Running   0          20m
vss-vss-deployment-xxxxx                                  1/1     Running   0          20m
```

### Get VSS Service URL

Wait for the LoadBalancer to get an external IP (~1-2 min):

```bash
kubectl get svc vss-service -n vss -w
```

Once you see an external IP:

```bash
EXTERNAL_IP=$(kubectl get svc vss-service -n vss -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "VSS UI:  http://$EXTERNAL_IP:9000"
echo "VSS API: http://$EXTERNAL_IP:8000"
```

### Check LLM Model Download Progress

The LLM (70B model) takes longest to download:

```bash
kubectl logs -n vss nim-llm-0 --tail=10
```

Expected Output (downloading):
```
Downloading model files...
Progress: 45%
```

Expected Output (ready):
```
INFO: Started server process
INFO: Uvicorn running on http://0.0.0.0:8000
```

---

## Troubleshooting

### ImageInspectError on Pods

If you deployed without the recommended command and see `ImageInspectError`, run:

```bash
helm upgrade vss nvidia-blueprint/nvidia-blueprint-vss -n vss --reuse-values \
  --set arango-db.image.repository=docker.io/arangodb \
  --set elasticsearch.image.repository=docker.elastic.co/elasticsearch/elasticsearch \
  --set milvus.image.repository=docker.io/milvusdb/milvus \
  --set milvus-minio.image.repository=docker.io/minio/minio \
  --set minio.image.repository=docker.io/minio/minio \
  --set neo4j.image.repository=docker.io/library/neo4j \
  --set vss.initContainers.checkLlmUp.image.repository=docker.io/curlimages/curl
```

### nemo-rerank CrashLoopBackOff (Permission Denied)

If nemo-rerank shows permission errors in logs:

```bash
helm upgrade vss nvidia-blueprint/nvidia-blueprint-vss -n vss --reuse-values \
  --set nemo-rerank.podSecurityContext.fsGroup=1000
```

### nim-llm CrashLoopBackOff (No Space Left)

If nim-llm fails with "No space left on device":

```bash
# Expand PVC to 200GB
kubectl patch pvc -n vss model-store-nim-llm-0 -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'

# Restart pod to pick up new size
kubectl delete pod -n vss nim-llm-0
```

### VSS Pod Stuck in Init:2/3

This is normal - VSS waits for the LLM to be healthy. Check LLM status:

```bash
kubectl logs -n vss nim-llm-0 --tail=10
```

Once LLM shows "Uvicorn running", VSS will start automatically.

### Pods Stuck in Pending (Insufficient GPU)

```bash
# Check GPU availability
kubectl describe nodes | grep -A5 "Allocated resources:" | grep gpu
```

VSS requires all 8 GPUs (H100) or 9 GPUs (A100). Ensure no other workloads are using GPUs.

### VSS Error: Failed to download Cosmos-Reason2-8B (401/403)

If you see:

```
huggingface_hub.errors.GatedRepoError: 401 Client Error
Cannot access gated repo for url https://huggingface.co/nvidia/Cosmos-Reason2-8B
```

or:

```
403 Client Error: Forbidden for url https://huggingface.co/nvidia/Cosmos-Reason2-8B
```

1. Go to https://huggingface.co/nvidia/Cosmos-Reason2-8B
2. Click **"Agree and access repository"** to accept the license
3. Get your token from https://huggingface.co/settings/tokens
4. Update the deployment:

```bash
export HF_TOKEN="<your-huggingface-token>"

kubectl set env deployment/vss-vss-deployment -n vss \
  HF_TOKEN=$HF_TOKEN \
  HUGGING_FACE_HUB_TOKEN=$HF_TOKEN

# Wait for new pod
kubectl rollout status deployment/vss-vss-deployment -n vss
```

### TensorRT Engine Warning

You may see: `"Using an engine plan file across different models of devices"`. This is informational and can be ignored. The model will still work correctly, though initialization may take a few extra minutes.

### Pod Stuck in FailedMount After Restart

If you see `"An operation for the volume already exists"`, scale the deployment down, wait for volumes to detach, then scale back up:

```bash
# Scale down to release volumes cleanly
kubectl scale deployment -n vss <deployment-name> --replicas=0

# Wait for volume detach
sleep 60

# Scale back up
kubectl scale deployment -n vss <deployment-name> --replicas=1
```

> **Tip**: Avoid using `kubectl delete pod --force` - let pods terminate gracefully to prevent this issue.

---

## Cleanup

To delete the VSS deployment and all associated resources:

```bash
# Delete Helm release
helm uninstall vss --namespace vss

# Wait for pods to terminate
echo "Waiting for pods to terminate..."
kubectl wait --for=delete pod -n vss --all --timeout=120s 2>/dev/null || true

# Delete all persistent volume claims
kubectl delete pvc -n vss --all

# Wait for volumes to detach from nodes
echo "Waiting 60s for OCI block volumes to detach..."
sleep 60

# Delete namespace
kubectl delete namespace vss

# Verify cleanup
kubectl get all -n vss 2>/dev/null && echo "WARNING: Some resources remain" || echo "Cleanup complete"
```

Expected Output:
```
release "vss" uninstalled
Waiting for pods to terminate...
persistentvolumeclaim "model-store-nim-llm-0" deleted
persistentvolumeclaim "nemo-embedding-nim-cache-pvc" deleted
persistentvolumeclaim "nemo-rerank-nim-cache-pvc" deleted
persistentvolumeclaim "vss-ngc-model-cache-pvc" deleted
persistentvolumeclaim "etcd-vss-cache-pvc" deleted
Waiting 60s for OCI block volumes to detach...
namespace "vss" deleted
Cleanup complete
```

> **Note**: The 60s wait ensures volumes are fully detached before redeploying.

---

## Deployment Checklist

Ensure the following are complete:

- [ ] OKE cluster is active and accessible
- [ ] GPU node pool is ready and healthy (see [Hardware Requirements](#hardware-requirements))
- [ ] NAT Gateway configured for outbound internet access
- [ ] NGC API key exported (`export NGC_API_KEY=...`)
- [ ] HuggingFace license accepted for `nvidia/Cosmos-Reason2-8B`
- [ ] HuggingFace token exported (`export HF_TOKEN=...`)
- [ ] Helm repo added (`helm repo list` shows nvidia-blueprint)
- [ ] Helm chart deployed
- [ ] All 11 pods in Running state (`kubectl get pods -n vss`)
- [ ] VSS service accessible

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
