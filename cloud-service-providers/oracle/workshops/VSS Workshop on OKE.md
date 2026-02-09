# Deploy Video Search and Summarization Using NVIDIA NIMs on Oracle Kubernetes Engine (OKE) Workshop

## Table of Contents

- [Introduction](#introduction)
- [What You Will Learn](#what-you-will-learn)
- [Learn the Components](#learn-the-components)
- [Setup and Requirements](#setup-and-requirements)
- [Task 1. Create OKE Cluster](#task-1-create-oke-cluster)
- [Task 2. Configure Cluster Access](#task-2-configure-cluster-access)
- [Task 3. Configure API Keys](#task-3-configure-api-keys)
- [Task 4. Deploy VSS Blueprint](#task-4-deploy-vss-blueprint)
- [Task 5. Monitor Deployment](#task-5-monitor-deployment)
- [Task 6. Access VSS Application](#task-6-access-vss-application)
- [Congratulations!](#congratulations)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)
- [Learn More](#learn-more)

## Introduction

This workshop will guide you through deploying the NVIDIA Video Search and Summarization (VSS) Blueprint on Oracle Kubernetes Engine (OKE). VSS enables intelligent video analysis using AI, combining Vision Language Models (VLM) with Large Language Models (LLM) to understand video content, extract insights, and enable natural language search across video libraries.

VSS transforms how organizations interact with video content by:

- **Understanding video content**: Using Vision Language Models to analyze frames and understand what's happening
- **Enabling natural language search**: Finding specific moments in videos using conversational queries
- **Generating summaries**: Automatically creating text summaries of video content
- **Multi-modal retrieval**: Combining text, visual, and semantic search capabilities

This workshop is ideal for developers and data scientists interested in:

- **Building video AI applications**: Learn how to deploy a complete video analysis pipeline.
- **Working with Vision Language Models**: Explore how VLMs understand and describe visual content.
- **Multi-database architectures**: Understand how multiple databases work together for video search.

## What You Will Learn

By the end of this workshop, you will have hands-on experience with:

1. **Deploying a video AI system on OKE**: Learn to deploy a complete video analysis pipeline with multiple AI models and databases.
2. **Working with Vision Language Models (VLM)**: Understand how VLMs analyze video frames and generate descriptions.
3. **Using multiple search modalities**: Explore vector search, graph search, and full-text search working together.
4. **Managing complex Kubernetes deployments**: Deploy and monitor a system with 11+ pods.

## Learn the Components

### GPUs in Oracle Kubernetes Engine (OKE)

VSS requires significant GPU resources for running multiple AI models simultaneously:

| Shape | GPUs | GPU Memory | VSS Support |
|-------|------|------------|-------------|
| BM.GPU.H100.8 | 8x H100 | 640 GB | ✅ Full |
| BM.GPU.A100-v2.8 | 8x A100 | 640 GB | ✅ Full (9 GPUs needed) |

### VSS Architecture

The VSS Blueprint consists of multiple integrated components:

```
┌─────────────────────────────────────────────────────────────────┐
│                         VSS Application                          │
│  ┌──────────────────┐  ┌──────────────────┐                     │
│  │   VSS Engine     │  │    LLM (70B)     │                     │
│  │  Video Analysis  │  │  Summarization   │                     │
│  └────────┬─────────┘  └────────┬─────────┘                     │
│           │                      │                               │
│           ▼                      ▼                               │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐ │
│  │   VLM (8B)       │  │    Embedder      │  │   Reranker    │ │
│  │  Frame Analysis  │  │  Text Vectors    │  │   Accuracy    │ │
│  └──────────────────┘  └──────────────────┘  └───────────────┘ │
│                              │                                   │
│           ┌──────────────────┼──────────────────┐               │
│           ▼                  ▼                  ▼               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   Milvus     │  │ Elasticsearch│  │    Neo4j     │          │
│  │Vector Search │  │  Text Search │  │ Graph Search │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

### Vision Language Model (VLM)

The VSS Blueprint uses **Cosmos-Reason2-8B**, NVIDIA's Vision Language Model that:

- Analyzes individual video frames
- Generates natural language descriptions of visual content
- Understands spatial relationships and actions
- Requires HuggingFace access (gated model)

### Large Language Model (LLM)

VSS uses **Llama 3.1 70B** for:

- Generating video summaries
- Answering natural language questions
- Synthesizing information from multiple frames

### Multi-Database Architecture

VSS uses multiple databases for different search capabilities:

| Database | Type | Purpose |
|----------|------|---------|
| **Milvus** | Vector | Semantic similarity search using embeddings |
| **Elasticsearch** | Full-text | Keyword and phrase search |
| **Neo4j** | Graph | Relationship-based queries |
| **ArangoDB** | Document | Structured metadata storage |
| **MinIO** | Object | Video file storage |

## Setup and Requirements

### What You Need

To complete this workshop, you need:

- **OCI Account** with access to GPU instances (H100 or A100)
- **OCI CLI** installed and configured
- **kubectl** command-line tool
- **Helm 3.x** package manager
- **NVIDIA NGC Account** - [Sign up here](https://ngc.nvidia.com/setup/api-key)
- **HuggingFace Account** with access to `nvidia/Cosmos-Reason2-8B` - [Accept license here](https://huggingface.co/nvidia/Cosmos-Reason2-8B)

### GPU Requirements

| Configuration | H100 80GB | A100 80GB |
|---------------|-----------|-----------|
| Full Blueprint | 8 | 9 |

**GPU Breakdown**:

| Component | H100 GPUs | A100 GPUs |
|-----------|-----------|-----------|
| VSS VLM (Cosmos-Reason2-8B) | 2 | 2 |
| LLM (Llama 3.1 70B) | 4 | 5 |
| Embedding NIM | 1 | 1 |
| Reranking NIM | 1 | 1 |
| **Total** | **8** | **9** |

> **Important**: A100 requires 9 GPUs total, but OKE's `BM.GPU.A100-v2.8` only has 8 GPUs. You may need to use the `BM.GPU4.8` shape or adjust the configuration.

### HuggingFace Access Required

The VSS Blueprint uses the `nvidia/Cosmos-Reason2-8B` model which requires accepting a license:

1. Go to [huggingface.co/nvidia/Cosmos-Reason2-8B](https://huggingface.co/nvidia/Cosmos-Reason2-8B)
2. Click **"Agree and access repository"**
3. Create a token at [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens) with **Read** access

### IAM Policy Requirements

Ensure your user/group has the following OCI permissions:

```
Allow group <GROUP_NAME> to manage instance-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to manage cluster-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to manage virtual-network-family in compartment <COMPARTMENT_NAME>
```

## Task 1. Create OKE Cluster

Create an OKE cluster with GPU nodes for VSS.

1. Navigate to **OCI Console** → **Developer Services** → **Kubernetes Clusters (OKE)**

2. Click **Create cluster** → Select **Quick create** → Click **Submit**

3. Configure the cluster:
   - **Name**: `vss-workshop`
   - **Kubernetes API endpoint**: Select **Public endpoint**
   - **Node type**: Select **Managed**
   - **Shape**: Select `BM.GPU.H100.8`
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

4. **Verify GPU availability** (should show 8 GPUs):

   ```bash
   kubectl describe nodes | grep -A5 "Allocatable:" | grep gpu
   ```

   Expected output:

   ```
     nvidia.com/gpu:     8
   ```

## Task 3. Configure API Keys

Configure access to NVIDIA NGC and HuggingFace.

1. **Export your API keys**:

   ```bash
   export NGC_API_KEY="<your-ngc-api-key>"
   export HF_TOKEN="<your-huggingface-token>"
   ```

   > **Note**: 
   > - NGC API key: [ngc.nvidia.com/setup/api-key](https://ngc.nvidia.com/setup/api-key)
   > - HuggingFace token: [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens)

2. **Verify HuggingFace access**:

   Ensure you've accepted the license for `nvidia/Cosmos-Reason2-8B` at [huggingface.co/nvidia/Cosmos-Reason2-8B](https://huggingface.co/nvidia/Cosmos-Reason2-8B)

3. **Remove GPU taints**:

   ```bash
   kubectl taint nodes --all nvidia.com/gpu:NoSchedule- 2>/dev/null || true
   ```

4. **Add NVIDIA Blueprint Helm repository**:

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

## Task 4. Deploy VSS Blueprint

Deploy the VSS Blueprint with all components.

1. **Deploy VSS Blueprint**:

   ```bash
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

   > **Note**: The `docker.io/` prefix is required on OKE because CRI-O enforces fully qualified image names.

   Expected output:

   ```
   NAME: vss
   LAST DEPLOYED: Mon Feb  3 10:00:00 2026
   NAMESPACE: vss
   STATUS: deployed
   REVISION: 1
   ```

2. **Understand what was deployed**:

   | Component | Purpose | GPUs |
   |-----------|---------|------|
   | `nim-llm-0` | Llama 3.1 70B for summarization | 4 |
   | `vss-vss-deployment-*` | VSS engine with VLM | 2 |
   | `nemo-embedding-*` | Text embeddings | 1 |
   | `nemo-rerank-*` | Search reranking | 1 |
   | `milvus-*` | Vector database | 0 |
   | `elasticsearch-*` | Full-text search | 0 |
   | `neo4j-*` | Graph database | 0 |
   | `arango-db-*` | Document store | 0 |
   | `minio-*` | Object storage | 0 |

## Task 5. Monitor Deployment

The deployment takes 15-20 minutes as large models need to be downloaded.

1. **Watch pod status**:

   ```bash
   kubectl get pods -n vss -w
   ```

   Initial state:

   ```
   NAME                                                      READY   STATUS              RESTARTS   AGE
   nim-llm-0                                                 0/1     Init:0/1            0          2m
   vss-vss-deployment-xxxxx                                  0/1     Init:0/3            0          2m
   elasticsearch-elasticsearch-deployment-xxxxx              0/1     ContainerCreating   0          2m
   ```

   Press `Ctrl+C` to exit.

2. **Check LLM download progress** (this takes the longest):

   ```bash
   kubectl logs -n vss nim-llm-0 --tail=20
   ```

   Downloading:

   ```
   Downloading model files...
   Progress: 45%
   ```

   When ready:

   ```
   INFO: Uvicorn running on http://0.0.0.0:8000
   ```

3. **Check VSS/VLM status**:

   The VSS pod waits for the LLM to be ready before starting:

   ```bash
   kubectl logs -n vss -l app=vss --tail=10
   ```

4. **Verify all pods are running** (after 15-20 minutes):

   ```bash
   kubectl get pods -n vss
   ```

   Expected output (11 pods running):

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

## Task 6. Access VSS Application

Access the VSS web interface and API.

1. **Get the LoadBalancer IP**:

   ```bash
   kubectl get svc vss-service -n vss -w
   ```

   Wait for `EXTERNAL-IP` (1-2 minutes), then press `Ctrl+C`.

2. **Get application URLs**:

   ```bash
   EXTERNAL_IP=$(kubectl get svc vss-service -n vss -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
   echo "VSS UI:  http://$EXTERNAL_IP:9000"
   echo "VSS API: http://$EXTERNAL_IP:8000"
   echo "API Docs: http://$EXTERNAL_IP:8000/docs"
   ```

3. **Access VSS UI**:

   Open `http://<EXTERNAL_IP>:9000` in your browser.

4. **Test VSS**:

   a. **Upload a video**: Click to upload a video file
   
   b. **Wait for processing**: The system analyzes frames and generates embeddings
   
   c. **Search**: Use natural language to search for moments in the video
   
   d. **View summaries**: See AI-generated summaries of video content

5. **Explore the API** (optional):

   Open `http://<EXTERNAL_IP>:8000/docs` to see the Swagger API documentation.

## Congratulations!

You've successfully deployed the NVIDIA Video Search and Summarization Blueprint on OKE!

**What you accomplished**:

- Created an OKE cluster with 8 H100 GPUs
- Deployed a complex multi-component video AI system
- Configured Vision Language Model with HuggingFace access
- Set up multiple databases for different search modalities
- Accessed the VSS interface for video analysis

**Key learnings**:

- VSS combines multiple AI models (VLM, LLM, Embedder, Reranker)
- Multi-database architecture enables different search types
- Vision Language Models can understand and describe video content

**Next steps**:

- Try different video types and search queries
- Explore the API for programmatic access
- Integrate VSS into your video management workflows

## Troubleshooting

### ImageInspectError on Pods

This happens when images don't have the `docker.io/` prefix. Fix with:

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
kubectl logs -n vss -l app=ranking --tail=20
```

Fix with:

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

This is **normal** - VSS waits for the LLM to be healthy. Check LLM status:

```bash
kubectl logs -n vss nim-llm-0 --tail=10
```

Once LLM shows "Uvicorn running", VSS will start automatically. This can take 15-20 minutes.

### Pods Stuck in Pending (Insufficient GPU)

Check GPU availability:

```bash
kubectl describe nodes | grep -A5 "Allocated resources:" | grep gpu
```

VSS requires all 8 GPUs (H100) or 9 GPUs (A100). Ensure no other workloads are using GPUs.

### VSS Error: Failed to download Cosmos-Reason2-8B (401/403)

If you see `GatedRepoError` or `403 Forbidden`:

1. Go to [huggingface.co/nvidia/Cosmos-Reason2-8B](https://huggingface.co/nvidia/Cosmos-Reason2-8B)
2. Click **"Agree and access repository"** to accept the license
3. Verify your token at [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens)
4. Update the deployment:

```bash
kubectl set env deployment/vss-vss-deployment -n vss \
  HF_TOKEN=$HF_TOKEN \
  HUGGING_FACE_HUB_TOKEN=$HF_TOKEN

kubectl rollout restart deployment/vss-vss-deployment -n vss
```

### TensorRT Engine Warning

You may see: `"Using an engine plan file across different models of devices"`. 

This is **informational and can be ignored**. The model will still work correctly, though initialization may take a few extra minutes.

### Pod Stuck in FailedMount After Restart

If you see `"An operation for the volume already exists"`:

```bash
# Scale down to release volumes cleanly
kubectl scale deployment -n vss vss-vss-deployment --replicas=0

# Wait for volume detach
sleep 60

# Scale back up
kubectl scale deployment -n vss vss-vss-deployment --replicas=1
```

> **Tip**: Avoid using `kubectl delete pod --force` - let pods terminate gracefully to prevent this issue.

---

## Cleanup

Clean up resources when done.

1. **Delete the Helm release**:

   ```bash
   helm uninstall vss --namespace vss
   ```

2. **Delete persistent volume claims**:

   ```bash
   kubectl delete pvc -n vss --all
   ```

3. **Wait for volumes to detach**:

   ```bash
   echo "Waiting 60s for OCI block volumes to detach..."
   sleep 60
   ```

4. **Delete the namespace**:

   ```bash
   kubectl delete namespace vss
   ```

5. **Delete OKE cluster** (optional - via OCI Console):
   
   Navigate to **OCI Console** → **Developer Services** → **Kubernetes Clusters** → Select your cluster → **Delete**

## Learn More

- [NVIDIA VSS Blueprint](https://github.com/NVIDIA-AI-Blueprints/video-search-and-summarization)
- [NVIDIA NIMs](https://www.nvidia.com/en-us/ai/)
- [Cosmos-Reason2-8B on HuggingFace](https://huggingface.co/nvidia/Cosmos-Reason2-8B)
- [Oracle Kubernetes Engine (OKE)](https://www.oracle.com/cloud/cloud-native/container-engine-kubernetes/)
- [Milvus Vector Database](https://milvus.io/)
- [Neo4j Graph Database](https://neo4j.com/)
