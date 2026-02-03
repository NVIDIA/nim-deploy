# Deploy AI-Q Research Assistant Using NVIDIA NIMs on Oracle Kubernetes Engine (OKE) Workshop

## Table of Contents

- [Introduction](#introduction)
- [What You Will Learn](#what-you-will-learn)
- [Learn the Components](#learn-the-components)
- [Setup and Requirements](#setup-and-requirements)
- [Task 1. Create OKE Cluster](#task-1-create-oke-cluster)
- [Task 2. Configure Cluster Access](#task-2-configure-cluster-access)
- [Task 3. Configure NVIDIA NGC API Key](#task-3-configure-nvidia-ngc-api-key)
- [Task 4. Deploy RAG Blueprint](#task-4-deploy-rag-blueprint)
- [Task 5. Verify RAG Deployment](#task-5-verify-rag-deployment)
- [Task 6. Deploy AIQ Blueprint](#task-6-deploy-aiq-blueprint)
- [Task 7. Verify AIQ Deployment](#task-7-verify-aiq-deployment)
- [Task 8. Access the AIQ Research Assistant](#task-8-access-the-aiq-research-assistant)
- [Congratulations!](#congratulations)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)
- [Learn More](#learn-more)

## Introduction

This workshop will guide you through deploying the NVIDIA AI-Q (AIQ) Research Assistant on Oracle Kubernetes Engine (OKE). AIQ is an AI-powered research assistant that combines agentic workflows with Retrieval Augmented Generation (RAG) capabilities to help users conduct research, analyze documents, and generate insights.

Unlike traditional chatbots that simply respond to queries, AIQ uses agentic workflows that can:

- **Plan**: Break down complex research tasks into steps
- **Execute**: Autonomously carry out research subtasks
- **Synthesize**: Combine findings into comprehensive responses

This workshop is ideal for developers and data scientists interested in:

- **Building agentic AI applications**: Learn how to deploy AI systems that can plan and execute complex tasks autonomously.
- **Combining multiple LLMs**: Explore how to use separate models for instruction-following and reasoning tasks.
- **Cross-namespace Kubernetes communication**: Understand how microservices communicate across namespaces.

## What You Will Learn

By the end of this workshop, you will have hands-on experience with:

1. **Deploying RAG as a foundation for AIQ**: Learn how AIQ builds on top of the RAG Blueprint for document ingestion and retrieval.
2. **Deploying AIQ with shared LLM configuration**: Configure AIQ to use the existing RAG LLM, saving GPU resources.
3. **Using cross-namespace service communication**: Understand how AIQ in the `aiq` namespace connects to RAG services in the `rag` namespace.
4. **Using the AIQ Research Assistant interface**: Conduct research tasks through the AIQ web interface.

## Learn the Components

### GPUs in Oracle Kubernetes Engine (OKE)

GPUs accelerate AI workloads running on your nodes. OKE provides GPU bare metal shapes:

| Shape | GPUs | GPU Memory |
|-------|------|------------|
| BM.GPU.H100.8 | 8x H100 | 640 GB |
| BM.GPU.A100-v2.8 | 8x A100 | 640 GB |

### NVIDIA AIQ (AI-Q Research Assistant)

[NVIDIA AIQ](https://github.com/NVIDIA-AI-Blueprints/aiq) is an agentic research assistant that:

- **Plans research tasks**: Breaks complex questions into subtasks
- **Executes autonomously**: Runs searches and analyzes documents
- **Uses multiple LLMs**: Combines instruction-following and reasoning models
- **Builds on RAG**: Leverages document retrieval for accurate responses

### Relationship Between AIQ and RAG

AIQ requires the RAG Blueprint as a foundation:

```
┌─────────────────────────────────────────────────────┐
│                    AIQ Blueprint                     │
│  ┌─────────────┐  ┌─────────────┐                   │
│  │ AIQ Backend │  │ AIQ Frontend│                   │
│  └──────┬──────┘  └─────────────┘                   │
│         │                                            │
│         │ Cross-namespace communication              │
│         ▼                                            │
├─────────────────────────────────────────────────────┤
│                    RAG Blueprint                     │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌────────┐ │
│  │   LLM   │  │ Embedder│  │ Reranker│  │ Milvus │ │
│  └─────────┘  └─────────┘  └─────────┘  └────────┘ │
└─────────────────────────────────────────────────────┘
```

### Shared LLM Configuration

In this workshop, we use a **shared LLM** configuration where AIQ uses the RAG Blueprint's LLM (Nemotron Super 49B) for both reasoning and instruction-following. This saves GPUs compared to deploying a separate LLM for AIQ.

| Configuration | Description | H100 GPUs | A100 GPUs |
|---------------|-------------|-----------|-----------|
| Text RAG + Shared LLM AIQ | AIQ uses RAG's LLM | 4 | 5 |
| Full RAG + Full AIQ | AIQ has its own LLM | 10 | 13 |

### NVIDIA NIMs

[NVIDIA NIMs](https://www.nvidia.com/en-us/ai/) are inference microservices that power both RAG and AIQ:

- **Nemotron Super 49B**: Large language model for text generation and reasoning
- **NeMo Embedder**: Converts text to vector embeddings
- **NeMo Reranker**: Improves search accuracy

## Setup and Requirements

### What You Need

To complete this workshop, you need:

- **OCI Account** with access to GPU instances (H100 or A100)
- **OCI CLI** installed and configured
- **kubectl** command-line tool
- **Helm 3.x** package manager
- **NVIDIA NGC Account** for an NGC API Key - [Sign up here](https://ngc.nvidia.com/setup/api-key)
- Sufficient OCI quota for GPU bare metal instances

### GPU Requirements

| Configuration | H100 80GB | A100 80GB |
|---------------|-----------|-----------|
| Text RAG + Shared LLM AIQ (this workshop) | 4 | 5 |
| Full RAG + Full AIQ | 10 | 13 |

> **Note**: This workshop uses the shared LLM configuration to minimize GPU requirements.

### IAM Policy Requirements

Ensure your user/group has the following OCI permissions:

```
Allow group <GROUP_NAME> to manage instance-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to manage cluster-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to manage virtual-network-family in compartment <COMPARTMENT_NAME>
```

## Task 1. Create OKE Cluster

Create an OKE cluster with GPU nodes.

1. Navigate to **OCI Console** → **Developer Services** → **Kubernetes Clusters (OKE)**

2. Click **Create cluster** → Select **Quick create** → Click **Submit**

3. Configure the cluster:
   - **Name**: `aiq-workshop`
   - **Kubernetes API endpoint**: Select **Public endpoint**
   - **Node type**: Select **Managed**
   - **Shape**: Select `BM.GPU.H100.8` or `BM.GPU.A100-v2.8`
   - **Number of nodes**: `1`
   - **Boot volume size**: `500` GB

4. Click **Create cluster**

5. Wait for the cluster to reach **Active** state (approximately 10-15 minutes)

## Task 2. Configure Cluster Access

Configure kubectl to access your cluster.

1. **Set environment variables**:

   ```bash
   export CLUSTER_ID="<your-cluster-ocid>"
   export REGION="<your-region>"
   ```

2. **Generate kubeconfig**:

   ```bash
   oci ce cluster create-kubeconfig --cluster-id $CLUSTER_ID --region $REGION \
     --file $HOME/.kube/config --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT
   ```

3. **Verify cluster access**:

   ```bash
   kubectl get nodes
   ```

   Expected output:

   ```
   NAME            STATUS   ROLES   AGE   VERSION
   10.0.10.xxx     Ready    node    10m   v1.28.2
   ```

4. **Verify GPU availability**:

   ```bash
   kubectl describe nodes | grep -A5 "Allocatable:" | grep gpu
   ```

   Expected output:

   ```
     nvidia.com/gpu:     8
   ```

## Task 3. Configure NVIDIA NGC API Key

Configure access to NVIDIA NGC.

1. **Export your NGC API key**:

   ```bash
   export NGC_API_KEY="<your-ngc-api-key>"
   ```

2. **Remove GPU taints**:

   ```bash
   kubectl taint nodes --all nvidia.com/gpu:NoSchedule- 2>/dev/null || true
   ```

3. **Add NVIDIA Blueprint Helm repository**:

   ```bash
   helm repo add nvidia-blueprint https://helm.ngc.nvidia.com/nvidia/blueprint \
     --username='$oauthtoken' --password=$NGC_API_KEY
   helm repo update
   ```

   Expected output:

   ```
   "nvidia-blueprint" has been added to your repositories
   Update Complete. ⎈Happy Helming!⎈
   ```

## Task 4. Deploy RAG Blueprint

AIQ requires the RAG Blueprint to be deployed first. RAG provides the document ingestion, embedding, and retrieval capabilities that AIQ builds upon.

1. **Deploy RAG Blueprint** (Text Only configuration):

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

   Expected output:

   ```
   NAME: rag
   LAST DEPLOYED: Mon Feb  3 10:00:00 2026
   NAMESPACE: rag
   STATUS: deployed
   REVISION: 1
   ```

2. **Understand what was deployed**:

   | Component | Namespace | Purpose | GPUs |
   |-----------|-----------|---------|------|
   | `rag-nim-llm-0` | rag | Nemotron Super 49B LLM | 1 (H100) / 2 (A100) |
   | `rag-nvidia-nim-*-embedqa-*` | rag | Embedding model | 1 |
   | `rag-nvidia-nim-*-rerankqa-*` | rag | Reranker | 1 |
   | `rag-nemoretriever-page-elements-*` | rag | Page layout | 1 |
   | `milvus-standalone-*` | rag | Vector database | 0 |

## Task 5. Verify RAG Deployment

Wait for all RAG pods to be ready before deploying AIQ.

1. **Watch RAG pod status** (wait 10-15 minutes):

   ```bash
   kubectl get pods -n rag -w
   ```

   Press `Ctrl+C` when all pods show `Running` status.

2. **Check LLM status**:

   ```bash
   kubectl logs -n rag rag-nim-llm-0 --tail=10
   ```

   When ready, you'll see:

   ```
   INFO: Uvicorn running on http://0.0.0.0:8000
   ```

3. **Verify all pods are running**:

   ```bash
   kubectl get pods -n rag
   ```

   All pods should show `1/1` READY and `Running` status.

4. **Test LLM endpoint**:

   ```bash
   kubectl exec -n rag deploy/rag-server -- curl -s http://nim-llm:8000/v1/health/ready
   ```

   Expected output:

   ```json
   {"status":"ready"}
   ```

## Task 6. Deploy AIQ Blueprint

Now deploy AIQ configured to use RAG's LLM (shared LLM configuration).

1. **Deploy AIQ Blueprint**:

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

   Expected output:

   ```
   NAME: aiq
   LAST DEPLOYED: Mon Feb  3 10:30:00 2026
   NAMESPACE: aiq
   STATUS: deployed
   REVISION: 1
   ```

2. **Understand the configuration**:

   | Setting | Value | Purpose |
   |---------|-------|---------|
   | `nim-llm.enabled=false` | Disable AIQ's LLM | Use RAG's LLM instead |
   | `INSTRUCT_BASE_URL` | `http://nim-llm.rag.svc.cluster.local:8000/v1` | Cross-namespace URL to RAG's LLM |
   | `INSTRUCT_MODEL_NAME` | `nvidia/llama-3.3-nemotron-super-49b-v1.5` | Model name for API calls |

3. **Understand what was deployed**:

   | Component | Namespace | Purpose | GPUs |
   |-----------|-----------|---------|------|
   | `aiq-aira-backend-*` | aiq | AIQ backend service | 0 |
   | `aiq-aira-frontend-*` | aiq | AIQ web interface | 0 |

   > **Note**: No LLM is deployed in the `aiq` namespace - it uses RAG's LLM via cross-namespace communication.

## Task 7. Verify AIQ Deployment

Verify AIQ is running and can communicate with RAG.

1. **Watch AIQ pod status**:

   ```bash
   kubectl get pods -n aiq -w
   ```

   Expected output (after 2-5 minutes):

   ```
   NAME                                READY   STATUS    RESTARTS   AGE
   aiq-aira-backend-xxxxx              1/1     Running   0          5m
   aiq-aira-frontend-xxxxx             1/1     Running   0          5m
   ```

2. **Verify AIQ can reach RAG's LLM**:

   ```bash
   kubectl exec -n aiq deploy/aiq-aira-backend -- curl -s http://nim-llm.rag.svc.cluster.local:8000/v1/health/ready
   ```

   Expected output:

   ```json
   {"status":"ready"}
   ```

3. **Check AIQ backend logs**:

   ```bash
   kubectl logs -n aiq -l app=aira-backend --tail=20
   ```

## Task 8. Access the AIQ Research Assistant

Access the AIQ web interface.

1. **Get the AIQ frontend LoadBalancer IP**:

   ```bash
   kubectl get svc aiq-aira-frontend -n aiq -w
   ```

   Wait for `EXTERNAL-IP` (1-2 minutes), then press `Ctrl+C`.

2. **Get both application URLs**:

   ```bash
   echo "AIQ Research Assistant: http://$(kubectl get svc aiq-aira-frontend -n aiq -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):3000"
   echo "RAG Playground: http://$(kubectl get svc rag-frontend -n rag -o jsonpath='{.status.loadBalancer.ingress[0].ip}'):3000"
   ```

3. **Test AIQ**:

   a. Open the **AIQ Research Assistant** URL in your browser
   
   b. First, upload documents through the **RAG Playground**
   
   c. Return to AIQ and ask complex research questions
   
   d. Observe how AIQ plans and executes research tasks

## Congratulations!

You've successfully deployed the NVIDIA AI-Q Research Assistant on OKE!

**What you accomplished**:

- Deployed the RAG Blueprint as a foundation
- Deployed AIQ with shared LLM configuration
- Configured cross-namespace service communication
- Accessed the AIQ Research Assistant interface

**Key learnings**:

- AIQ builds on RAG for document retrieval capabilities
- Shared LLM configuration saves GPU resources
- Kubernetes cross-namespace DNS enables service communication

**Next steps**:

- Try complex research questions that require multiple steps
- Explore deploying Full AIQ with its own LLM for better performance
- Integrate AIQ into your applications using its API

## Troubleshooting

### AIQ Pods Not Starting

Check pod events for errors:

```bash
kubectl describe pod -n aiq -l app=aira-backend
```

Check AIQ backend logs:

```bash
kubectl logs -n aiq -l app=aira-backend --tail=30
```

### AIQ Cannot Connect to RAG LLM

This is the most common issue. Verify RAG LLM is running:

```bash
kubectl get pods -n rag | grep nim-llm
```

Expected output:

```
rag-nim-llm-0   1/1     Running   0   45m
```

Test LLM endpoint from AIQ pod:

```bash
kubectl exec -n aiq deploy/aiq-aira-backend -- curl -s http://nim-llm.rag.svc.cluster.local:8000/v1/health/ready
```

Expected output:

```json
{"status":"ready"}
```

If the connection fails, verify RAG is fully deployed:

```bash
kubectl get pods -n rag
```

All pods should be `Running` before deploying AIQ.

### AIQ Cannot Connect to RAG Server

Verify RAG server is running:

```bash
kubectl get pods -n rag | grep rag-server
```

Check RAG server logs:

```bash
kubectl logs -n rag -l app=rag-server --tail=20
```

### NGC Authentication Errors (ImagePullBackOff)

Verify your API key:

```bash
echo $NGC_API_KEY
```

Check secrets exist in both namespaces:

```bash
kubectl get secret -n rag | grep ngc
kubectl get secret -n aiq | grep ngc
```

### RAG Pods Not Ready Before AIQ Deployment

If you deployed AIQ before RAG was fully ready:

1. Delete AIQ:
   ```bash
   helm uninstall aiq -n aiq
   ```

2. Wait for RAG to be fully ready:
   ```bash
   kubectl get pods -n rag -w
   ```

3. Redeploy AIQ once all RAG pods show `Running`.

---

## Cleanup

Clean up resources when done.

1. **Delete AIQ**:

   ```bash
   helm uninstall aiq --namespace aiq
   kubectl delete namespace aiq
   ```

2. **Delete RAG**:

   ```bash
   helm uninstall rag --namespace rag
   kubectl delete pvc -n rag --all
   echo "Waiting 60s for volumes to detach..."
   sleep 60
   kubectl delete namespace rag
   ```

3. **Delete OKE cluster** (optional - via OCI Console):
   
   Navigate to **OCI Console** → **Developer Services** → **Kubernetes Clusters** → Select your cluster → **Delete**

## Learn More

- [NVIDIA AIQ Blueprint](https://github.com/NVIDIA-AI-Blueprints/aiq)
- [NVIDIA RAG Blueprint](https://github.com/NVIDIA-AI-Blueprints/rag)
- [NVIDIA NIMs](https://www.nvidia.com/en-us/ai/)
- [Oracle Kubernetes Engine (OKE)](https://www.oracle.com/cloud/cloud-native/container-engine-kubernetes/)
