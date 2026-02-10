# NVIDIA AI Virtual Assistant Blueprint on Oracle Kubernetes Engine (OKE)

This guide provides step-by-step instructions for deploying the NVIDIA AI Virtual Assistant Blueprint on Oracle Cloud Infrastructure (OCI) using Oracle Kubernetes Engine (OKE) and GPU instances.

> *For the most up-to-date information, licensing, and terms of use, please refer to the [NVIDIA AI Virtual Assistant Blueprint](https://github.com/NVIDIA-AI-Blueprints/ai-virtual-assistant).*

## Overview

The NVIDIA AI Virtual Assistant Blueprint is a reference solution for a text-based virtual assistant that enhances customer service operations using [NVIDIA NIM](https://developer.nvidia.com/nim) microservices and Retrieval Augmented Generation (RAG). It enables context-aware, multi-turn conversations and provides general and personalized Q&A responses based on structured and unstructured data, such as order history and product details.

This blueprint demonstrates how to deploy the AI Virtual Assistant on OKE using the Helm chart provided in the blueprint repository, with OKE-specific configuration for fully qualified container image names and LoadBalancer access to the web UI.

### Key Features

- Context-aware, multi-turn customer service conversations
- Integration with NVIDIA NeMo Retriever and NVIDIA NIM for embeddings, reranking, and LLM inference
- Structured data (CSV) and unstructured data (PDF) ingestion with Milvus vector store
- Sample customer service agent user interface and API-based analytics server
- LangGraph-based orchestrator with LangChain text retrievers

### Architecture Components

| Component | Purpose |
|-----------|---------|
| NIM LLM (Inference) | Llama 3.1 70B Instruct - response generation |
| NeMo Embedding | Text embeddings for semantic search |
| NeMo Rerank | Rerank search results for accuracy |
| Agent Services | LangGraph-based orchestration and agent logic |
| API Gateway | Request routing and API exposure |
| AI Virtual Assistant UI | Customer service agent web interface |
| Retriever (Canonical) | Unstructured data retrieval |
| Retriever (Structured) | Structured data retrieval |
| Milvus | Vector database for embeddings |
| MinIO | Object storage for documents |
| PostgreSQL | Structured data and checkpointer |
| etcd | Metadata storage |
| Redis / Redis Commander | Cache and cache management |
| pgAdmin | PostgreSQL administration (optional) |

## Prerequisites

Before starting the deployment process, ensure you have the following:

- **Oracle Cloud Infrastructure (OCI) Account** with access to GPU instances
- **NVIDIA NGC Account** for an **NGC API Key** to pull container images. Sign up at [ngc.nvidia.com](https://ngc.nvidia.com/setup/api-key)
- **OCI CLI** installed and configured/authenticated
- **kubectl** Kubernetes command-line tool
- **Helm 3.x** package manager for Kubernetes
- **Git** (to clone the blueprint repository)

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
| Full Blueprint (self-hosted NIMs) | 8 | 8 |

> **Note**: Pipeline operations can share GPUs with NIMs; 1x L40 or similar is recommended for Milvus. For optimal performance, use dedicated GPUs for the LLM NIM (8x H100 or 8x A100 for Llama 3.1 70B).

**Additional Requirements:**
- **Boot Volume**: Minimum 500 GB

**Cluster size (nodes):**

| Nodes | Configuration |
|-------|---------------|
| **1** | Full Blueprint (8 GPUs) |

---

## Infrastructure Setup

This section covers the steps to prepare your OCI infrastructure for running the AI Virtual Assistant Blueprint.

### Console Quick Create (Recommended)

The fastest way — auto-provisions networking.

1. Go to **OCI Console** → **Developer Services** → **Kubernetes Clusters (OKE)**
2. Click **Create cluster** → Select **Quick create** → **Submit**
3. Configure:
   - Name: `gpu-cluster`
   - Kubernetes API endpoint: **Public endpoint**
   - Shape: Select GPU shape based on [Hardware Requirements](#hardware-requirements) (e.g., 8x H100 or 8x A100)
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

> **Already have a cluster?** Start here — whether you have an existing cluster or just created one above.

#### 1. Verify Storage Size

Check that your node's storage matches your boot volume size:

```bash
kubectl describe nodes | grep ephemeral-storage | head -1
```

If you specified a 500 GB boot volume, you should see ~`512628992Ki` (~489 GB). If you see ~`37206272Ki` (~35 GB), the volume needs expanding; continue to step 2. Otherwise, skip to step 3.

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

# Verify (should now show ~512628992Ki for 500 GB)
sleep 10 && kubectl describe nodes | grep ephemeral-storage | head -1
```

**Option B: Via SSH (if you have node access)**

```bash
sudo /usr/libexec/oci-growfs -y
sudo systemctl restart kubelet
```

#### 3. Set Up Cluster

```bash
# Remove GPU taints
kubectl taint nodes --all nvidia.com/gpu:NoSchedule- 2>/dev/null || true

# Verify GPU resources
kubectl describe nodes | grep -A5 "Allocatable:" | grep gpu
```

Expected Output:
```
node/10.0.10.xx untainted
  nvidia.com/gpu:             8
```

---

## Clone the Blueprint Repository

The AI Virtual Assistant Helm chart is deployed from the blueprint repository (not the NGC Helm catalog). Clone the repository and use the chart in `deploy/helm`.

```bash
git clone https://github.com/NVIDIA-AI-Blueprints/ai-virtual-assistant.git
cd ai-virtual-assistant/deploy/helm
```

---

## Deployment

### 1. Create Namespace and Secrets

```bash
export NGC_API_KEY="<your-ngc-api-key>"
kubectl create namespace aiva --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry ngc-docker-reg-secret -n aiva \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password="$NGC_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic ngc-secret -n aiva \
  --from-literal=ngc-api-key="$NGC_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -
```

Expected Output:
```
namespace/aiva created
secret/ngc-docker-reg-secret created
secret/ngc-secret created
```

### 2. Install the AI Virtual Assistant Helm Chart

Run the following from the `ai-virtual-assistant/deploy/helm` directory (you should already be there after the [Clone the Blueprint Repository](#clone-the-blueprint-repository) step). The `docker.io/` prefixes are **required** on OKE because CRI-O enforces fully qualified image names.

```bash
helm upgrade --install aiva . --namespace aiva \
  --set global.ngcImagePullSecretName=ngc-docker-reg-secret \
  --set 'ranking-ms.applicationSpecs.ranking-deployment.containers.ranking-container.env[0].name=NGC_API_KEY' \
  --set "ranking-ms.applicationSpecs.ranking-deployment.containers.ranking-container.env[0].value=$NGC_API_KEY" \
  --set 'nemollm-inference.applicationSpecs.nemollm-infer-deployment.containers.nemollm-infer-container.env[0].name=NGC_API_KEY' \
  --set "nemollm-inference.applicationSpecs.nemollm-infer-deployment.containers.nemollm-infer-container.env[0].value=$NGC_API_KEY" \
  --set 'nemollm-embedding.applicationSpecs.embedding-deployment.containers.embedding-container.env[0].name=NGC_API_KEY' \
  --set "nemollm-embedding.applicationSpecs.embedding-deployment.containers.embedding-container.env[0].value=$NGC_API_KEY" \
  --set milvus.applicationSpecs.milvus-deployment.containers.milvus-container.image.repository=docker.io/milvusdb/milvus \
  --set minio.applicationSpecs.minio-deployment.containers.minio-container.image.repository=docker.io/minio/minio \
  --set postgres.applicationSpecs.postgres-deployment.containers.postgres-container.image.repository=docker.io/library/postgres \
  --set cache-services.applicationSpecs.cache-services-deployment.containers.redis-container.image.repository=docker.io/library/redis \
  --set cache-services.applicationSpecs.cache-services-deployment.containers.rediscommander-container.image.repository=docker.io/rediscommander/redis-commander \
  --set pgadmin.applicationSpecs.pgadmin-deployment.containers.pgadmin-container.image.repository=docker.io/dpage/pgadmin4 \
  --set aiva-ui.service.type=LoadBalancer
```

Expected Output:
```
Release "aiva" does not exist. Installing it now.
NAME: aiva
LAST DEPLOYED: <date>
NAMESPACE: aiva
STATUS: deployed
REVISION: 1
```

> **Note**: Use single quotes around `--set` keys that contain brackets (e.g., `'ranking-ms...env[0].name=...'`) to avoid shell expansion. Use double quotes for values that reference `$NGC_API_KEY`.

---

## Verification

### Monitor Deployment Status

Wait for pods to be ready (15-30 minutes for NIM model download and init dependencies):

```bash
kubectl get pods -n aiva -w
```

Expected Output (initial state):
```
NAME                                                           READY   STATUS              RESTARTS   AGE
agent-services-agent-services-deployment-xxxxx                 0/1     Init:0/1            0          2m
aiva-aiva-ui-xxxxx                                             0/1     Init:0/1            0          2m
analytics-services-analytics-deployment-xxxxx                  1/1     Running             0          2m
...
```

Expected Output (after 15-30 minutes):
```
NAME                                                          READY   STATUS    RESTARTS   AGE
agent-services-agent-services-deployment-xxxxx                1/1     Running   0          25m
aiva-aiva-ui-xxxxx                                            1/1     Running   0          25m
analytics-services-analytics-deployment-xxxxx                 1/1     Running   0          25m
api-gateway-api-gateway-deployment-xxxxx                      1/1     Running   0          25m
cache-services-cache-services-deployment-xxxxx                2/2     Running   0          25m
etcd-etcd-deployment-xxxxx                                    1/1     Running   0          25m
ingest-client-ingest-client-deployment-xxxxx                  1/1     Running   0          25m
milvus-milvus-deployment-xxxxx                                1/1     Running   0          25m
minio-minio-deployment-xxxxx                                  1/1     Running   0          25m
nemollm-embedding-embedding-deployment-xxxxx                   1/1     Running   0          25m
nemollm-inference-nemollm-infer-deployment-xxxxx               1/1     Running   0          25m
pgadmin-pgadmin-deployment-xxxxx                               1/1     Running   0          25m
postgres-postgres-deployment-xxxxx                             1/1     Running   0          25m
ranking-ms-ranking-deployment-xxxxx                            1/1     Running   0          25m
retriever-canonical-canonical-deployment-xxxxx                 1/1     Running   0          25m
retriever-structured-structured-deployment-xxxxx               1/1     Running   0          25m
```

### Get AI Virtual Assistant UI URL

```bash
echo "AI Virtual Assistant UI: http://$(kubectl get svc aiva-aiva-ui -n aiva -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):3001"
```

Expected Output:
```
AI Virtual Assistant UI: http://158.xxx.xxx.xxx:3001
```

### Expected Pods

After deployment completes, you should see these pods running:

```bash
kubectl get pods -n aiva
```

| Pod Name Pattern | Description |
|-----------------|-------------|
| `agent-services-agent-services-deployment-*` | LangGraph agent orchestration |
| `aiva-aiva-ui-*` | Customer service agent web UI |
| `analytics-services-analytics-deployment-*` | Analytics API |
| `api-gateway-api-gateway-deployment-*` | API gateway |
| `cache-services-cache-services-deployment-*` | Redis and Redis Commander |
| `etcd-etcd-deployment-*` | etcd metadata store |
| `ingest-client-ingest-client-deployment-*` | Ingestion client |
| `milvus-milvus-deployment-*` | Milvus vector database |
| `minio-minio-deployment-*` | MinIO object storage |
| `nemollm-embedding-embedding-deployment-*` | NeMo embedding NIM |
| `nemollm-inference-nemollm-infer-deployment-*` | NeMo LLM inference NIM |
| `pgadmin-pgadmin-deployment-*` | pgAdmin (optional) |
| `postgres-postgres-deployment-*` | PostgreSQL |
| `ranking-ms-ranking-deployment-*` | Reranker NIM |
| `retriever-canonical-canonical-deployment-*` | Unstructured retriever |
| `retriever-structured-structured-deployment-*` | Structured retriever |

---

## Troubleshooting

### Pods Stuck in Pending

```bash
# Check for GPU taints
kubectl describe nodes | grep -i taint
```

Expected Output (should show no taints):
```
Taints:             <none>
```

```bash
# Check GPU availability
kubectl describe nodes | grep -A5 "Allocated resources:" | grep gpu
```

Expected Output (example when GPUs are allocated):
```
  nvidia.com/gpu                 8           8
```

### ImageInspectError (Short Image Names)

On OKE, CRI-O enforces fully qualified image names. If you see `ImageInspectError` with messages like "short name mode is enforcing, but image name redis:7.0.13 returns ambiguous list", upgrade the release with the OKE image overrides from [Deployment](#deployment) step 2 (all `--set ...repository=docker.io/...` and the same NGC_API_KEY sets).

### Init Containers Waiting on Dependencies

Agent-services and api-gateway init containers wait for backend services (retrievers, nemollm-inference). The LLM NIM (`nemollm-inference`) can take 10-20 minutes to become ready while the model loads. Check readiness:

```bash
kubectl get pods -n aiva | grep nemollm-inference
kubectl logs -n aiva -l app.kubernetes.io/name=nemollm-inference --tail=20
```

### NGC Authentication Errors (ImagePullBackOff)

```bash
# Verify API key is set
echo $NGC_API_KEY
```

```bash
# Check secrets exist
kubectl get secret -n aiva ngc-docker-reg-secret ngc-secret
```

Expected Output:
```
NAME                     TYPE                             DATA   AGE
ngc-docker-reg-secret    kubernetes.io/dockerconfigjson   1      10m
ngc-secret               Opaque                           1      10m
```

---

## Cleanup

To delete the AI Virtual Assistant deployment and all associated resources:

```bash
# Delete Helm release
helm uninstall aiva --namespace aiva

# Wait for pods to terminate
echo "Waiting for pods to terminate..."
kubectl wait --for=delete pod -n aiva --all --timeout=120s 2>/dev/null || true

# Delete all persistent volume claims
kubectl delete pvc -n aiva --all

# Wait for volumes to detach from nodes
echo "Waiting 60s for OCI block volumes to detach..."
sleep 60

# Delete namespace
kubectl delete namespace aiva

# Verify cleanup
kubectl get all -n aiva 2>/dev/null && echo "WARNING: Some resources remain" || echo "Cleanup complete"
```

Expected Output:
```
release "aiva" uninstalled
Waiting for pods to terminate...
persistentvolumeclaim "..." deleted
...
Waiting 60s for OCI block volumes to detach...
namespace "aiva" deleted
Cleanup complete
```

---

## Deployment Checklist

Ensure the following are complete:

- [ ] OKE cluster is active and accessible
- [ ] GPU node pool is ready and healthy (see [Hardware Requirements](#hardware-requirements))
- [ ] NAT Gateway configured for outbound internet access
- [ ] NGC API key exported (`export NGC_API_KEY=...`)
- [ ] Blueprint repository cloned and `cd ai-virtual-assistant/deploy/helm`
- [ ] Namespace `aiva` and secrets created
- [ ] Helm chart deployed successfully (`helm list -n aiva`)
- [ ] All pods in Running state (`kubectl get pods -n aiva`)
- [ ] AI Virtual Assistant UI LoadBalancer has external IP
- [ ] AI Virtual Assistant UI accessible at `http://<EXTERNAL-IP>:3001`

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

Then continue with [Pre-Deployment Setup](#pre-deployment-setup), then [Clone the Blueprint Repository](#clone-the-blueprint-repository), then [Deployment](#deployment).
