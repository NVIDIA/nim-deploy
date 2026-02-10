# NVIDIA Data Flywheel Blueprint on Oracle Kubernetes Engine (OKE)

This guide provides step-by-step instructions for deploying the NVIDIA Data Flywheel Blueprint on Oracle Cloud Infrastructure (OCI) using Oracle Kubernetes Engine (OKE) and GPU instances.

> *For the most up-to-date information, licensing, and terms of use, please refer to the [NVIDIA Data Flywheel Blueprint](https://github.com/NVIDIA-AI-Blueprints/data-flywheel).*

## Overview

The NVIDIA Data Flywheel Blueprint provides a systematic, automated solution to refine and redeploy optimized models using [NVIDIA NIM](https://developer.nvidia.com/nim). It establishes a self-reinforcing data flywheel using production traffic logs and institutional knowledge to continuously improve model efficiency and accuracy.

### Key Features

- Continuous model optimization using production data
- Automated evaluation across multiple candidate models
- LoRA-based fine-tuning with NeMo Customizer
- LLM-as-judge evaluation for quality assessment
- REST API for job management and monitoring
- MLflow integration for experiment tracking

### Architecture Components

| Component | Purpose |
|-----------|---------|
| Data Flywheel API | FastAPI service for job management |
| Celery Workers | Async task processing |
| NeMo Evaluator | Model evaluation service |
| NeMo Customizer | LoRA fine-tuning |
| NIM Proxy | Model inference routing |
| Elasticsearch | Production log storage |
| MongoDB | Job and config storage |
| Redis | Task queue |
| MLflow | Experiment tracking |
| PostgreSQL | Metadata storage |

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
| With Remote LLM Judge | 2 | 2 |
| With Self-hosted LLM Judge | 6 | 6 |

This guide uses the **Remote LLM Judge** configuration (2 GPUs minimum).

**Additional Requirements:**
- **Boot Volume**: Minimum 500 GB
- **Block Storage**: ~100 GB for databases (auto-provisioned via PVCs)

---

## Infrastructure Setup

This section covers the steps to prepare your OCI infrastructure for running the Data Flywheel Blueprint.

### Console Quick Create (Recommended)

The fastest way — auto-provisions networking.

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

Deploy the Data Flywheel Blueprint:

```bash
# Create namespace
kubectl create namespace nv-nvidia-blueprint-data-flywheel

# Create required secrets
kubectl create secret generic nvidia-api -n nv-nvidia-blueprint-data-flywheel \
  --from-literal=NVIDIA_API_KEY="$NGC_API_KEY"
kubectl create secret generic ngc-api -n nv-nvidia-blueprint-data-flywheel \
  --from-literal=NGC_API_KEY="$NGC_API_KEY"
kubectl create secret generic hf-secret -n nv-nvidia-blueprint-data-flywheel \
  --from-literal=HF_TOKEN=""
kubectl create secret generic llm-judge-api -n nv-nvidia-blueprint-data-flywheel \
  --from-literal=LLM_JUDGE_API_KEY="$NGC_API_KEY"
kubectl create secret generic emb-api -n nv-nvidia-blueprint-data-flywheel \
  --from-literal=EMB_API_KEY="$NGC_API_KEY"
kubectl create secret docker-registry nvcrimagepullsecret \
  -n nv-nvidia-blueprint-data-flywheel \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password=$NGC_API_KEY

# Deploy with remote LLM judge (no Volcano scheduler required)
helm install data-flywheel nvidia-blueprint/nvidia-blueprint-data-flywheel \
  --namespace nv-nvidia-blueprint-data-flywheel \
  --set volcano.enabled=false \
  --set data-flywheel-nemo-operator.volcano.install=false \
  --set foundationalFlywheelServer.config.llm_judge_config.deployment_type=remote \
  --set foundationalFlywheelServer.config.icl_config.similarity_config.embedding_nim_config.deployment_type=remote \
  --timeout 10m
```

Expected Output:
```
NAME: data-flywheel
LAST DEPLOYED: Sat Jan 31 03:48:16 2026
NAMESPACE: nv-nvidia-blueprint-data-flywheel
STATUS: deployed
REVISION: 1
```

---

## Verification

### Monitor Deployment Status

Wait for pods to be ready (5-10 minutes):

```bash
kubectl get pods -n nv-nvidia-blueprint-data-flywheel -w
```

Expected Output (after 5-10 minutes):
```
NAME                                                              READY   STATUS    RESTARTS   AGE
data-flywheel-data-store-xxxxx                                    1/1     Running   0          5m
data-flywheel-deployment-management-xxxxx                         1/1     Running   0          5m
data-flywheel-entity-store-xxxxx                                  1/1     Running   0          5m
data-flywheel-entity-storedb-0                                    1/1     Running   0          5m
data-flywheel-evaluator-xxxxx                                     2/2     Running   0          5m
data-flywheel-evaluatordb-0                                       1/1     Running   0          5m
data-flywheel-guardrails-xxxxx                                    1/1     Running   0          5m
data-flywheel-guardrailsdb-0                                      1/1     Running   0          5m
data-flywheel-nemo-operator-controller-manager-xxxxx              2/2     Running   0          5m
data-flywheel-nim-operator-xxxxx                                  1/1     Running   0          5m
data-flywheel-nim-proxy-xxxxx                                     1/1     Running   0          5m
data-flywheel-postgresql-0                                        1/1     Running   0          5m
df-api-deployment-xxxxx                                           1/1     Running   0          5m
df-celery-parent-worker-deployment-xxxxx                          1/1     Running   0          5m
df-celery-worker-deployment-xxxxx                                 1/1     Running   0          5m
df-elasticsearch-deployment-xxxxx                                 1/1     Running   0          5m
df-mlflow-deployment-xxxxx                                        1/1     Running   0          5m
df-mongodb-deployment-xxxxx                                       1/1     Running   0          5m
df-redis-deployment-xxxxx                                         1/1     Running   0          5m
```

### Get API Service URL

Expose the API via LoadBalancer:

```bash
kubectl patch svc df-api-service -n nv-nvidia-blueprint-data-flywheel \
  -p '{"spec":{"type":"LoadBalancer"}}'
```

Wait for external IP (~1-2 minutes):

```bash
kubectl get svc df-api-service -n nv-nvidia-blueprint-data-flywheel -w
```

Once you see an external IP:

```bash
EXTERNAL_IP=$(kubectl get svc df-api-service -n nv-nvidia-blueprint-data-flywheel \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "API Docs: http://$EXTERNAL_IP:8000/docs"
```

---

## Using the API

### Access Swagger UI

Open in your browser:
```
http://<EXTERNAL_IP>:8000/docs
```

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/jobs` | GET | List all flywheel jobs |
| `/api/jobs` | POST | Create a new flywheel job |
| `/api/jobs/{job_id}` | GET | Get job details |
| `/api/jobs/{job_id}` | DELETE | Delete a job |
| `/api/jobs/{job_id}/cancel` | POST | Cancel a running job |

### Example: Create a Flywheel Job

```bash
curl -X POST "http://$EXTERNAL_IP:8000/api/jobs" \
  -H "Content-Type: application/json" \
  -d '{
    "workload_id": "my-workload",
    "client_id": "my-client",
    "data_split_config": {
      "eval_size": 20,
      "val_ratio": 0.1,
      "min_total_records": 50,
      "limit": 10000
    }
  }'
```

**Response:**
```json
{
  "id": "65f8a1b2c3d4e5f6a7b8c9d0",
  "status": "queued",
  "message": "NIM workflow started"
}
```

---

## How to Use the Data Flywheel

### Understanding the Flywheel Concept

The Data Flywheel continuously optimizes your AI deployments by:

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   Production    →    Curate    →    Evaluate    →    Deploy    │
│     Logs             Data          Candidates        Best      │
│       ↑                                               │        │
│       └───────────── Continuous Loop ─────────────────┘        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

1. **Collect**: Gathers production traffic logs from Elasticsearch
2. **Curate**: Filters and prepares datasets for evaluation
3. **Evaluate**: Tests smaller/cheaper candidate models against the source model
4. **Deploy**: Surfaces the most efficient model that meets accuracy targets

### Workflow Stages

A flywheel job progresses through these stages:

| Stage | Description |
|-------|-------------|
| `queued` | Job is queued and waiting to start |
| `pending` | Job is initializing |
| `deploying-nim` | Deploying NIM models for evaluation |
| `running-evals` | Running evaluations on candidate models |
| `completed` | Job finished successfully |
| `failed` | Job encountered an error |
| `cancelled` | Job was cancelled by user |

### Step 1: Ingest Production Logs

Before running a flywheel job, you need data in Elasticsearch. The built-in Elasticsearch is available at:

```bash
# Get Elasticsearch URL
ES_IP=$(kubectl get svc df-elasticsearch-service -n nv-nvidia-blueprint-data-flywheel \
  -o jsonpath='{.spec.clusterIP}')
echo "Elasticsearch: http://$ES_IP:9200"
```

**Index sample data** (for testing):

```bash
# Port forward to Elasticsearch
kubectl port-forward svc/df-elasticsearch-service 9200:9200 \
  -n nv-nvidia-blueprint-data-flywheel &

# Create an index with sample logs
curl -X POST "http://localhost:9200/production-logs/_doc" \
  -H "Content-Type: application/json" \
  -d '{
    "timestamp": "2026-01-31T10:00:00Z",
    "prompt": "What is the capital of France?",
    "response": "The capital of France is Paris.",
    "model": "llama-3.1-70b-instruct",
    "latency_ms": 450,
    "tokens": 25
  }'

# Add more logs as needed...
```

### Step 2: Create a Flywheel Job

Create a job to run the NIM workflow on your workload:

```bash
curl -X POST "http://$EXTERNAL_IP:8000/api/jobs" \
  -H "Content-Type: application/json" \
  -d '{
    "workload_id": "my-workload",
    "client_id": "my-client",
    "data_split_config": {
      "eval_size": 20,
      "val_ratio": 0.1,
      "min_total_records": 50,
      "limit": 10000
    }
  }'
```

**Response:**
```json
{
  "id": "65f8a1b2c3d4e5f6a7b8c9d0",
  "status": "queued",
  "message": "NIM workflow started"
}
```

### Step 3: Monitor Job Progress

**Check job status:**

```bash
JOB_ID="65f8a1b2c3d4e5f6a7b8c9d0"
curl "http://$EXTERNAL_IP:8000/api/jobs/$JOB_ID"
```

**Response:**
```json
{
  "id": "65f8a1b2c3d4e5f6a7b8c9d0",
  "workload_id": "my-workload",
  "client_id": "my-client",
  "status": "running",
  "started_at": "2026-01-31T10:00:00Z",
  "num_records": 1000,
  "llm_judge": {
    "model_name": "meta/llama-3.3-70b-instruct",
    "type": "remote",
    "deployment_status": "ready"
  },
  "nims": [
    {
      "model_name": "meta/llama-3.1-8b-instruct",
      "status": "running-evals",
      "deployment_status": "ready",
      "runtime_seconds": 120.5,
      "evaluations": []
    }
  ],
  "datasets": [
    {"name": "eval_dataset", "num_records": 100}
  ]
}
```

**List all jobs:**

```bash
curl "http://$EXTERNAL_IP:8000/api/jobs"
```

### Step 4: View Results

Once the job completes, the results include evaluation scores:

```bash
curl "http://$EXTERNAL_IP:8000/api/jobs/$JOB_ID"
```

**Response:**
```json
{
  "id": "65f8a1b2c3d4e5f6a7b8c9d0",
  "workload_id": "my-workload",
  "client_id": "my-client",
  "status": "completed",
  "started_at": "2026-01-31T10:00:00Z",
  "finished_at": "2026-01-31T10:15:00Z",
  "num_records": 1000,
  "nims": [
    {
      "model_name": "meta/llama-3.1-8b-instruct",
      "status": "completed",
      "deployment_status": "ready",
      "runtime_seconds": 300.5,
      "evaluations": [
        {
          "eval_type": "accuracy",
          "scores": {
            "function_name_and_args_accuracy": 0.95,
            "score": 0.92
          },
          "started_at": "2026-01-31T10:05:00Z",
          "finished_at": "2026-01-31T10:10:00Z",
          "runtime_seconds": 300.0,
          "progress": 100.0,
          "mlflow_uri": "http://localhost:5000/#/experiments/123"
        }
      ],
      "customizations": []
    }
  ],
  "datasets": [
    {"name": "eval_dataset", "num_records": 100},
    {"name": "train_dataset", "num_records": 800}
  ]
}
```

### Step 5: Access MLflow for Experiment Tracking

Expose MLflow UI to view detailed experiment results:

```bash
kubectl patch svc df-mlflow-service -n nv-nvidia-blueprint-data-flywheel \
  -p '{"spec":{"type":"LoadBalancer"}}'

MLFLOW_IP=$(kubectl get svc df-mlflow-service -n nv-nvidia-blueprint-data-flywheel \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "MLflow UI: http://$MLFLOW_IP:5000"
```

MLflow tracks:
- Evaluation metrics for each candidate model
- Fine-tuning artifacts and checkpoints
- Model comparison visualizations

### Cancel or Delete a Job

**Cancel a running job:**
```bash
curl -X POST "http://$EXTERNAL_IP:8000/api/jobs/$JOB_ID/cancel"
```

**Delete a completed job:**
```bash
curl -X DELETE "http://$EXTERNAL_IP:8000/api/jobs/$JOB_ID"
```

### Key Concepts

| Term | Description |
|------|-------------|
| `workload_id` | Identifier for the workload/application being optimized |
| `client_id` | Identifier for the client or tenant |
| `NIM` | NVIDIA Inference Microservice - a model deployment |
| `LLM Judge` | Model used to evaluate response quality |
| `Evaluation` | Test run comparing model outputs against ground truth |
| `Customization` | LoRA fine-tuning to improve model performance |

---

## Troubleshooting

### Pods Stuck in Pending (FailedCreate)

If you see errors about `volcano-admission-service`, delete leftover Volcano webhooks:

```bash
kubectl delete mutatingwebhookconfiguration -l app.kubernetes.io/name=volcano 2>/dev/null || true
kubectl delete validatingwebhookconfiguration -l app.kubernetes.io/name=volcano 2>/dev/null || true

# Also try by pattern
kubectl get mutatingwebhookconfiguration | grep volcano | awk '{print $1}' | \
  xargs kubectl delete mutatingwebhookconfiguration 2>/dev/null || true
kubectl get validatingwebhookconfiguration | grep volcano | awk '{print $1}' | \
  xargs kubectl delete validatingwebhookconfiguration 2>/dev/null || true

# Restart deployments
kubectl rollout restart deployment -n nv-nvidia-blueprint-data-flywheel
```

### Pods in CreateContainerConfigError

This usually means secrets are missing or have the wrong key names. Recreate them:

```bash
kubectl delete secret nvidia-api ngc-api hf-secret llm-judge-api emb-api \
  -n nv-nvidia-blueprint-data-flywheel 2>/dev/null || true

kubectl create secret generic nvidia-api -n nv-nvidia-blueprint-data-flywheel \
  --from-literal=NVIDIA_API_KEY="$NGC_API_KEY"
kubectl create secret generic ngc-api -n nv-nvidia-blueprint-data-flywheel \
  --from-literal=NGC_API_KEY="$NGC_API_KEY"
kubectl create secret generic hf-secret -n nv-nvidia-blueprint-data-flywheel \
  --from-literal=HF_TOKEN=""
kubectl create secret generic llm-judge-api -n nv-nvidia-blueprint-data-flywheel \
  --from-literal=LLM_JUDGE_API_KEY="$NGC_API_KEY"
kubectl create secret generic emb-api -n nv-nvidia-blueprint-data-flywheel \
  --from-literal=EMB_API_KEY="$NGC_API_KEY"

kubectl rollout restart deployment -n nv-nvidia-blueprint-data-flywheel
```

### StatefulSets Not Starting

If PostgreSQL or other database pods are stuck:

```bash
# Check events
kubectl get events -n nv-nvidia-blueprint-data-flywheel --sort-by='.lastTimestamp' | tail -20

# Check PVC status
kubectl get pvc -n nv-nvidia-blueprint-data-flywheel
```

### API Returns 404 on Root Path

This is expected. Use `/docs` for the Swagger UI or `/api/jobs` for the API.

---

## Cleanup

To delete the Data Flywheel deployment and all associated resources:

```bash
# Delete Helm release
helm uninstall data-flywheel --namespace nv-nvidia-blueprint-data-flywheel

# Wait for pods to terminate
echo "Waiting for pods to terminate..."
kubectl wait --for=delete pod -n nv-nvidia-blueprint-data-flywheel --all --timeout=120s 2>/dev/null || true

# Delete all persistent volume claims
kubectl delete pvc -n nv-nvidia-blueprint-data-flywheel --all

# Wait for volumes to detach from nodes
echo "Waiting 60s for OCI block volumes to detach..."
sleep 60

# Delete namespace
kubectl delete namespace nv-nvidia-blueprint-data-flywheel

# Clean up any leftover cluster resources
kubectl delete clusterrole -l app.kubernetes.io/instance=data-flywheel 2>/dev/null || true
kubectl delete clusterrolebinding -l app.kubernetes.io/instance=data-flywheel 2>/dev/null || true

# Verify cleanup
kubectl get all -n nv-nvidia-blueprint-data-flywheel 2>/dev/null && \
  echo "WARNING: Some resources remain" || echo "Cleanup complete"
```

Expected Output:
```
release "data-flywheel" uninstalled
Waiting for pods to terminate...
persistentvolumeclaim "data-data-flywheel-postgresql-0" deleted
persistentvolumeclaim "data-data-flywheel-entity-storedb-0" deleted
...
Waiting 60s for OCI block volumes to detach...
namespace "nv-nvidia-blueprint-data-flywheel" deleted
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
- [ ] Secrets created before Helm install
- [ ] Helm chart deployed
- [ ] All 19 pods in Running state
- [ ] API service accessible via LoadBalancer

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
