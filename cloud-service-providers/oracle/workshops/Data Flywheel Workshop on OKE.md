# Deploy Data Flywheel for Model Optimization on Oracle Kubernetes Engine (OKE) Workshop

## Table of Contents

- [Introduction](#introduction)
- [What You Will Learn](#what-you-will-learn)
- [Learn the Components](#learn-the-components)
- [Setup and Requirements](#setup-and-requirements)
- [Task 1. Create OKE Cluster](#task-1-create-oke-cluster)
- [Task 2. Configure Cluster Access](#task-2-configure-cluster-access)
- [Task 3. Configure NVIDIA NGC API Key](#task-3-configure-nvidia-ngc-api-key)
- [Task 4. Create Required Secrets](#task-4-create-required-secrets)
- [Task 5. Deploy Data Flywheel Blueprint](#task-5-deploy-data-flywheel-blueprint)
- [Task 6. Monitor Deployment](#task-6-monitor-deployment)
- [Task 7. Access the API](#task-7-access-the-api)
- [Task 8. Create a Flywheel Job](#task-8-create-a-flywheel-job)
- [Congratulations!](#congratulations)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)
- [Learn More](#learn-more)

## Introduction

This workshop will guide you through deploying the NVIDIA Data Flywheel Blueprint on Oracle Kubernetes Engine (OKE). The Data Flywheel provides a systematic, automated solution to continuously improve AI model efficiency and accuracy using production traffic logs.

The Data Flywheel concept is a self-reinforcing cycle:

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

This workshop is ideal for ML engineers and platform teams interested in:

- **Continuous model optimization**: Learn how to automatically improve models using production data.
- **Automated evaluation pipelines**: Build systems that evaluate candidate models against your requirements.
- **MLOps best practices**: Understand how to track experiments and compare model performance.

## What You Will Learn

By the end of this workshop, you will have hands-on experience with:

1. **Deploying a model optimization pipeline**: Learn to deploy the Data Flywheel with all its components (API, workers, databases, MLflow).
2. **Managing flywheel jobs via REST API**: Create, monitor, and manage optimization jobs programmatically.
3. **Using MLflow for experiment tracking**: Track evaluations and compare model performance.
4. **Understanding the flywheel workflow**: Learn how production data flows through curation, evaluation, and deployment stages.

## Learn the Components

### The Data Flywheel Concept

The Data Flywheel continuously optimizes your AI deployments through these stages:

| Stage | Description |
|-------|-------------|
| **Collect** | Gather production traffic logs from Elasticsearch |
| **Curate** | Filter and prepare datasets for evaluation |
| **Evaluate** | Test smaller/cheaper candidate models against the source model |
| **Deploy** | Surface the most efficient model that meets accuracy targets |

### GPUs in Oracle Kubernetes Engine (OKE)

The Data Flywheel has flexible GPU requirements depending on configuration:

| Configuration | H100 80GB | A100 80GB | Description |
|---------------|-----------|-----------|-------------|
| Remote LLM Judge | 2 | 2 | Uses NVIDIA API for evaluation |
| Self-hosted LLM Judge | 6 | 6 | Runs LLM judge locally |

This workshop uses the **Remote LLM Judge** configuration (2 GPUs minimum).

### Architecture Components

```
┌─────────────────────────────────────────────────────────────────┐
│                      Data Flywheel                               │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │  Flywheel    │  │   Celery     │  │    NIM       │          │
│  │    API       │  │   Workers    │  │   Proxy      │          │
│  └──────┬───────┘  └──────┬───────┘  └──────────────┘          │
│         │                  │                                     │
│         ▼                  ▼                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   MongoDB    │  │    Redis     │  │ Elasticsearch│          │
│  │  Job Store   │  │ Task Queue   │  │   Log Store  │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   MLflow     │  │  PostgreSQL  │  │    NeMo      │          │
│  │  Tracking    │  │   Metadata   │  │  Customizer  │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

### Component Details

| Component | Purpose |
|-----------|---------|
| **Data Flywheel API** | FastAPI service for creating and managing flywheel jobs |
| **Celery Workers** | Asynchronous task processing for evaluations |
| **NIM Proxy** | Routes inference requests to model endpoints |
| **NeMo Evaluator** | Runs model evaluations |
| **NeMo Customizer** | Performs LoRA fine-tuning |
| **Elasticsearch** | Stores production traffic logs |
| **MongoDB** | Stores job configurations and state |
| **Redis** | Task queue for Celery workers |
| **MLflow** | Experiment tracking and model comparison |
| **PostgreSQL** | Metadata storage for MLflow |

### LLM Judge Configuration

The Data Flywheel uses an "LLM Judge" to evaluate response quality. Two configurations are available:

| Configuration | Description | GPUs | Cost |
|---------------|-------------|------|------|
| **Remote** | Uses NVIDIA API endpoints | 2 | Lower GPU, API costs |
| **Self-hosted** | Runs LLM judge locally | 6 | Higher GPU, no API costs |

This workshop uses the **Remote** configuration.

## Setup and Requirements

### What You Need

To complete this workshop, you need:

- **OCI Account** with access to GPU instances
- **OCI CLI** installed and configured
- **kubectl** command-line tool
- **Helm 3.x** package manager
- **NVIDIA NGC Account** for an NGC API Key - [Sign up here](https://ngc.nvidia.com/setup/api-key)
- Sufficient OCI quota for GPU instances

### GPU Requirements

| Configuration | H100 80GB | A100 80GB |
|---------------|-----------|-----------|
| Remote LLM Judge (this workshop) | 2 | 2 |
| Self-hosted LLM Judge | 6 | 6 |

> **Note**: The Remote LLM Judge configuration requires only 2 GPUs, making it suitable for smaller GPU shapes.

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
   - **Name**: `flywheel-workshop`
   - **Kubernetes API endpoint**: Select **Public endpoint**
   - **Node type**: Select **Managed**
   - **Shape**: Select a GPU shape with at least 2 GPUs (e.g., `BM.GPU.H100.8`, `VM.GPU.A10.2`)
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

## Task 4. Create Required Secrets

The Data Flywheel requires several Kubernetes secrets before deployment.

1. **Create the namespace**:

   ```bash
   kubectl create namespace nv-nvidia-blueprint-data-flywheel
   ```

2. **Create NVIDIA API secret** (for remote LLM judge):

   ```bash
   kubectl create secret generic nvidia-api -n nv-nvidia-blueprint-data-flywheel \
     --from-literal=NVIDIA_API_KEY="$NGC_API_KEY"
   ```

3. **Create NGC API secret** (for container pulls):

   ```bash
   kubectl create secret generic ngc-api -n nv-nvidia-blueprint-data-flywheel \
     --from-literal=NGC_API_KEY="$NGC_API_KEY"
   ```

4. **Create HuggingFace secret** (empty for this workshop):

   ```bash
   kubectl create secret generic hf-secret -n nv-nvidia-blueprint-data-flywheel \
     --from-literal=HF_TOKEN=""
   ```

5. **Create LLM Judge API secret**:

   ```bash
   kubectl create secret generic llm-judge-api -n nv-nvidia-blueprint-data-flywheel \
     --from-literal=LLM_JUDGE_API_KEY="$NGC_API_KEY"
   ```

6. **Create Embedding API secret**:

   ```bash
   kubectl create secret generic emb-api -n nv-nvidia-blueprint-data-flywheel \
     --from-literal=EMB_API_KEY="$NGC_API_KEY"
   ```

7. **Create image pull secret**:

   ```bash
   kubectl create secret docker-registry nvcrimagepullsecret \
     -n nv-nvidia-blueprint-data-flywheel \
     --docker-server=nvcr.io \
     --docker-username='$oauthtoken' \
     --docker-password=$NGC_API_KEY
   ```

8. **Verify secrets were created**:

   ```bash
   kubectl get secrets -n nv-nvidia-blueprint-data-flywheel
   ```

   Expected output:

   ```
   NAME                  TYPE                             DATA   AGE
   emb-api               Opaque                           1      10s
   hf-secret             Opaque                           1      10s
   llm-judge-api         Opaque                           1      10s
   ngc-api               Opaque                           1      10s
   nvidia-api            Opaque                           1      10s
   nvcrimagepullsecret   kubernetes.io/dockerconfigjson   1      10s
   ```

## Task 5. Deploy Data Flywheel Blueprint

Deploy the Data Flywheel with remote LLM judge configuration.

1. **Deploy the Helm chart**:

   ```bash
   helm install data-flywheel nvidia-blueprint/nvidia-blueprint-data-flywheel \
     --namespace nv-nvidia-blueprint-data-flywheel \
     --set volcano.enabled=false \
     --set data-flywheel-nemo-operator.volcano.install=false \
     --set foundationalFlywheelServer.config.llm_judge_config.deployment_type=remote \
     --set foundationalFlywheelServer.config.icl_config.similarity_config.embedding_nim_config.deployment_type=remote \
     --timeout 10m
   ```

   Expected output:

   ```
   NAME: data-flywheel
   LAST DEPLOYED: Mon Feb  3 10:00:00 2026
   NAMESPACE: nv-nvidia-blueprint-data-flywheel
   STATUS: deployed
   REVISION: 1
   ```

2. **Understand the configuration**:

   | Setting | Value | Purpose |
   |---------|-------|---------|
   | `volcano.enabled=false` | Disable Volcano scheduler | Not needed for remote config |
   | `llm_judge_config.deployment_type=remote` | Use NVIDIA API | External LLM judge |
   | `embedding_nim_config.deployment_type=remote` | Use NVIDIA API | External embeddings |

## Task 6. Monitor Deployment

Monitor the deployment progress (5-10 minutes).

1. **Watch pod status**:

   ```bash
   kubectl get pods -n nv-nvidia-blueprint-data-flywheel -w
   ```

   Press `Ctrl+C` when pods are running.

2. **Verify all pods are running** (approximately 19 pods):

   ```bash
   kubectl get pods -n nv-nvidia-blueprint-data-flywheel
   ```

   Expected output:

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

3. **Check for any issues**:

   ```bash
   kubectl get events -n nv-nvidia-blueprint-data-flywheel --sort-by='.lastTimestamp' | tail -10
   ```

## Task 7. Access the API

Expose and access the Data Flywheel API.

1. **Expose the API via LoadBalancer**:

   ```bash
   kubectl patch svc df-api-service -n nv-nvidia-blueprint-data-flywheel \
     -p '{"spec":{"type":"LoadBalancer"}}'
   ```

2. **Wait for external IP**:

   ```bash
   kubectl get svc df-api-service -n nv-nvidia-blueprint-data-flywheel -w
   ```

   Wait for `EXTERNAL-IP` (1-2 minutes), then press `Ctrl+C`.

3. **Get the API URL**:

   ```bash
   EXTERNAL_IP=$(kubectl get svc df-api-service -n nv-nvidia-blueprint-data-flywheel \
     -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
   echo "API Docs: http://$EXTERNAL_IP:8000/docs"
   echo "API Base: http://$EXTERNAL_IP:8000/api"
   ```

4. **Test API health**:

   ```bash
   curl -s "http://$EXTERNAL_IP:8000/health" | head
   ```

5. **Open Swagger UI**:

   Open `http://<EXTERNAL_IP>:8000/docs` in your browser to explore the API.

## Task 8. Create a Flywheel Job

Create and monitor a flywheel job using the API.

1. **List existing jobs** (should be empty):

   ```bash
   curl -s "http://$EXTERNAL_IP:8000/api/jobs" | python3 -m json.tool
   ```

   Expected output:

   ```json
   []
   ```

2. **Create a flywheel job**:

   ```bash
   curl -X POST "http://$EXTERNAL_IP:8000/api/jobs" \
     -H "Content-Type: application/json" \
     -d '{
       "workload_id": "test-workload",
       "client_id": "workshop-user",
       "data_split_config": {
         "eval_size": 20,
         "val_ratio": 0.1,
         "min_total_records": 50,
         "limit": 10000
       }
     }'
   ```

   Expected output:

   ```json
   {
     "id": "65f8a1b2c3d4e5f6a7b8c9d0",
     "status": "queued",
     "message": "NIM workflow started"
   }
   ```

3. **Monitor job status**:

   ```bash
   JOB_ID="<job-id-from-previous-step>"
   curl -s "http://$EXTERNAL_IP:8000/api/jobs/$JOB_ID" | python3 -m json.tool
   ```

4. **Access MLflow for experiment tracking** (optional):

   ```bash
   kubectl patch svc df-mlflow-service -n nv-nvidia-blueprint-data-flywheel \
     -p '{"spec":{"type":"LoadBalancer"}}'
   
   MLFLOW_IP=$(kubectl get svc df-mlflow-service -n nv-nvidia-blueprint-data-flywheel \
     -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
   echo "MLflow UI: http://$MLFLOW_IP:5000"
   ```

## Congratulations!

You've successfully deployed the NVIDIA Data Flywheel Blueprint on OKE!

**What you accomplished**:

- Created an OKE cluster with GPU nodes
- Configured required secrets for the Data Flywheel
- Deployed the Data Flywheel with remote LLM judge configuration
- Accessed the API and created a flywheel job
- Explored MLflow for experiment tracking

**Key learnings**:

- Data Flywheel automates model optimization using production data
- Remote LLM judge reduces GPU requirements
- REST API enables programmatic job management
- MLflow provides experiment tracking and comparison

**Next steps**:

- Ingest production logs into Elasticsearch
- Run complete flywheel cycles with real data
- Compare candidate models using MLflow
- Integrate with your CI/CD pipeline

## Troubleshooting

### Pods Stuck in Pending (FailedCreate)

If you see errors about `volcano-admission-service`, delete leftover Volcano webhooks:

```bash
kubectl delete mutatingwebhookconfiguration -l app.kubernetes.io/name=volcano 2>/dev/null || true
kubectl delete validatingwebhookconfiguration -l app.kubernetes.io/name=volcano 2>/dev/null || true

# Restart deployments
kubectl rollout restart deployment -n nv-nvidia-blueprint-data-flywheel
```

### Pods in CreateContainerConfigError

This usually means secrets are missing or have wrong key names. Recreate them:

```bash
# Delete existing secrets
kubectl delete secret nvidia-api ngc-api hf-secret llm-judge-api emb-api \
  -n nv-nvidia-blueprint-data-flywheel 2>/dev/null || true

# Recreate secrets
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

# Restart deployments
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

If PVCs are stuck in `Pending`, check storage class availability:

```bash
kubectl get storageclass
```

### API Returns 404 on Root Path

This is **expected behavior**. The API has no root endpoint.

Use these paths instead:
- Swagger UI: `http://<IP>:8000/docs`
- API endpoints: `http://<IP>:8000/api/jobs`
- Health check: `http://<IP>:8000/health`

### Celery Workers Not Processing Jobs

Check worker logs:

```bash
kubectl logs -n nv-nvidia-blueprint-data-flywheel -l app=celery-worker --tail=30
```

Verify Redis is running:

```bash
kubectl get pods -n nv-nvidia-blueprint-data-flywheel | grep redis
```

### MongoDB Connection Errors

Check MongoDB pod status:

```bash
kubectl get pods -n nv-nvidia-blueprint-data-flywheel | grep mongodb
kubectl logs -n nv-nvidia-blueprint-data-flywheel -l app=mongodb --tail=20
```

---

## Cleanup

Clean up resources when done.

1. **Delete the Helm release**:

   ```bash
   helm uninstall data-flywheel --namespace nv-nvidia-blueprint-data-flywheel
   ```

2. **Delete persistent volume claims**:

   ```bash
   kubectl delete pvc -n nv-nvidia-blueprint-data-flywheel --all
   ```

3. **Wait for volumes to detach**:

   ```bash
   echo "Waiting 60s for OCI block volumes to detach..."
   sleep 60
   ```

4. **Delete the namespace**:

   ```bash
   kubectl delete namespace nv-nvidia-blueprint-data-flywheel
   ```

5. **Clean up cluster resources**:

   ```bash
   kubectl delete clusterrole -l app.kubernetes.io/instance=data-flywheel 2>/dev/null || true
   kubectl delete clusterrolebinding -l app.kubernetes.io/instance=data-flywheel 2>/dev/null || true
   ```

6. **Delete OKE cluster** (optional - via OCI Console):
   
   Navigate to **OCI Console** → **Developer Services** → **Kubernetes Clusters** → Select your cluster → **Delete**

## Learn More

- [NVIDIA Data Flywheel Blueprint](https://github.com/NVIDIA-AI-Blueprints/data-flywheel)
- [NVIDIA NeMo Customizer](https://developer.nvidia.com/nemo-microservices)
- [MLflow](https://mlflow.org/)
- [Oracle Kubernetes Engine (OKE)](https://www.oracle.com/cloud/cloud-native/container-engine-kubernetes/)
