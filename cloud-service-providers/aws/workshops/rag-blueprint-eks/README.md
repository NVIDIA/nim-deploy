# Deploy NVIDIA Enterprise RAG Blueprint on Amazon Elastic Kubernetes Service (EKS) Workshop

## Table of Contents

- [Diagram](#diagram)
- [Introduction](#introduction)
- [What you will learn](#what-you-will-learn)
- [Learn the Components](#learn-the-components)
- [Setup and Requirements](#setup-and-requirements)
- [Task 1. Infrastructure Deployment](#task-1-infrastructure-deployment)
- [Task 2. Configure NVIDIA NGC API Key](#task-2-configure-nvidia-ngc-api-key)
- [Task 3. Install NVIDIA GPU Operator](#task-3-install-nvidia-gpu-operator)
- [Task 4. Deploy Storage Class](#task-4-deploy-storage-class)
- [Task 5. Deploy Enterprise RAG Blueprint](#task-5-deploy-enterprise-rag-blueprint)
- [Task 6. Access the RAG Frontend Service](#task-6-access-the-rag-frontend-service)
- [Task 7. Test the RAG Application](#task-7-test-the-rag-application)
- [Congratulations!](#congratulations)
- [Cleanup and Uninstallation](#cleanup-and-uninstallation)

## Diagram

![Enterprise RAG Blueprint Architecture](imgs/architecture.png)

**Enterprise RAG Blueprint Architecture:**

The NVIDIA Enterprise RAG Blueprint provides a comprehensive solution for Retrieval Augmented Generation, featuring:

- **Reasoning Model**: `llama-3.1-nemotron-nano-8b-v1` for intelligent query processing
- **Report Generation Model**: `meta/llama-3.1-8b-instruct` for generating comprehensive responses
- **NeMo Retriever Embedding**: `llama-3.2-nv-embedqa-1b-v2` for semantic search
- **NeMo Retriever Reranking**: `llama-3.2-nv-rerankqa-1b-v2` for improved relevance
- **Page Elements Model**: `nemoretriever-page-elements-v2` for document understanding
- **Vector Database**: Milvus for efficient embedding storage and retrieval
- **Frontend**: React-based RAG Playground for user interaction

## Introduction

This workshop will guide you through deploying the complete [NVIDIA Enterprise RAG Blueprint](https://build.nvidia.com/nvidia/build-an-enterprise-rag-pipeline) on Amazon Elastic Kubernetes Service (EKS). You'll leverage the power of NVIDIA Inference Microservices (NIMs) and NeMo Retriever to build a production-ready retrieval augmented generation system optimized for enterprise workloads. For more deployment details of this blueprint, see the [Github Repository](https://github.com/NVIDIA-AI-Blueprints/rag/tree/main)

We will be deploying the [text-only](https://github.com/NVIDIA-AI-Blueprints/rag/blob/main/docs/text_only_ingest.md) ingestion portion for this Blueprint

This workshop is ideal for developers, data scientists, and architects interested in:

- **Building enterprise-grade RAG applications**: Learn how to deploy a complete, production-ready RAG pipeline using NVIDIA's enterprise blueprint.
- **Optimizing GPU utilization**: Explore how to efficiently deploy multiple AI models across GPU resources for maximum performance.
- **Leveraging advanced retrieval**: Understand how to implement sophisticated embedding and reranking models for improved accuracy.
- **Scaling AI workloads**: Learn to manage and scale complex AI deployments using Kubernetes orchestration.

## What you will learn

By the end of this workshop, you will have hands-on experience with:

1. **Deploying the Enterprise RAG Blueprint on EKS**: Learn to deploy a complete enterprise-grade RAG solution including multiple NIM models, vector databases, and frontend services onto your EKS cluster.
2. **Managing GPU resources efficiently**: Understand how to optimize GPU allocation across multiple AI models for cost-effective deployment.
3. **Integrating advanced retrieval components**: Gain familiarity with NeMo Retriever's embedding and reranking capabilities for superior document understanding.
4. **Operating production RAG systems**: Explore techniques for monitoring, scaling, and maintaining enterprise RAG deployments using Kubernetes best practices.

## Learn the Components

### NVIDIA Enterprise RAG Blueprint

The [NVIDIA Enterprise RAG Blueprint](https://build.nvidia.com/nvidia/build-an-enterprise-rag-pipeline) is a comprehensive, production-ready solution that combines multiple NVIDIA AI microservices to deliver enterprise-grade retrieval augmented generation capabilities. It includes optimized models for reasoning, embedding, reranking, and document processing.

### GPUs in Amazon Elastic Kubernetes Service (EKS)

GPUs accelerate AI workloads running on your nodes, particularly machine learning inference and training. EKS provides a range of GPU-enabled instance types including A10G, L40S, A100, and H100 GPUs, allowing you to choose the optimal configuration for your workload requirements.

### NVIDIA NIMs (NVIDIA Inference Microservices)

[NVIDIA NIMs](https://www.nvidia.com/en-us/ai/) are containerized AI inference microservices that provide easy-to-deploy, scalable, and secure AI model serving. NIMs include optimized runtimes, pre-built containers, and enterprise support for production deployments.

### NVIDIA NeMo Retriever

[NVIDIA NeMo Retriever](https://developer.nvidia.com/blog/develop-production-grade-text-retrieval-pipelines-for-rag-with-nvidia-nemo-retriever) provides state-of-the-art embedding and reranking models specifically designed for enterprise RAG applications. It includes specialized models for different document types and retrieval scenarios.

### RAG Server and Ingestor

The blueprint includes dedicated microservices for:
- **RAG Server**: Handles query processing, retrieval orchestration, and response generation
- **Ingestor Server**: Manages document processing, embedding generation, and vector database population
- **NV-Ingest**: Advanced document processing pipeline supporting multiple content types

### Vector Database Integration

The blueprint integrates with Milvus vector database, providing GPU-accelerated similarity search, advanced indexing capabilities, and horizontal scaling for large-scale document collections.

## Setup and Requirements

### What you need

To complete this lab, you need:

- Access to a standard internet browser (Chrome browser recommended).
- Access to an AWS Account with access to GPU instances (g5.12xlarge recommended). You will need a minimum of **7 A10G GPUs** (2 x g5.12xlarge instances) for the optimized deployment.
- Sufficient AWS IAM permissions to create EKS clusters and manage resources.
- An [NVIDIA NGC API Key](https://org.ngc.nvidia.com/setup/personal-keys) for accessing NVIDIA container registry and models.
- Time to complete the lab (approximately 2-3 hours).

### GPU Requirements

The optimized deployment requires:

**Main Node Group (2 x g5.12xlarge instances = 8 total A10G GPUs, using 7):**
1. **Reasoning Model** (`llama-3.1-nemotron-nano-8b-v1`) → 2 A10G GPUs
2. **Report Generation Model** (`meta/llama-3.1-8b-instruct`) → 2 A10G GPUs  
3. **NeMo Retriever Embedding Model** (`llama-3.2-nv-embedqa-1b-v2`) → 1 A10G GPU
4. **NeMo Retriever Reranking Model** (`llama-3.2-nv-rerankqa-1b-v2`) → 1 A10G GPU
5. **Page Elements Model** (`nemoretriever-page-elements-v2`) → 1 A10G GPU

### How to start your lab and sign in to the AWS Console

### Activate Cloud Shell

Cloud Shell is a virtual machine loaded with development tools. It offers a persistent home directory and runs on the AWS Cloud, providing command-line access to your AWS resources.

In the AWS Console, in the top right toolbar, click the **Activate Cloud Shell** button.

![AWS Cloud Shell](imgs/aws-cloudshell.png)

It takes a few moments to provision and connect to the environment.

![AWS Cloud Shell Starting](imgs/aws-cloudshell-start.png)

`AWS CLI` is the command-line tool for AWS Cloud. It comes pre-installed on Cloud Shell and supports tab-completion.

## Task 1. Infrastructure Deployment

1. **Open Cloud Shell** and install prerequisites:

   The Cloud Shell environment comes preinstalled with `kubectl`, the native CLI tool to manage Kubernetes objects within your Amazon EKS clusters.

   Install additional required tools:
   - `eksctl` - The CLI used to work with EKS clusters
   - `helm` - The Kubernetes package manager

   **Install `eksctl`:**

   ```bash
   # for ARM systems, set ARCH to: `arm64`, `armv6` or `armv7`
   ARCH=amd64
   PLATFORM=$(uname -s)_$ARCH

   curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"

   # (Optional) Verify checksum
   curl -sL "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_checksums.txt" | grep $PLATFORM | sha256sum --check

   tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz

   sudo mv /tmp/eksctl /usr/local/bin
   ```

   **Install `helm`:**

   ```bash
   curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
   chmod 700 get_helm.sh
   ./get_helm.sh
   ```

2. **Set Environment Variables**

   Configure the deployment parameters for your EKS cluster:

   ```bash
   # Cluster & AWS region
   export CLUSTER_NAME="nvidia-enterprise-rag"
   export REGION="us-east-1"

   # Node group names
   export MAIN_NG="main-ng"

   # Instance types & sizes
   export GPU_INSTANCE_TYPE="g5.12xlarge"
   export MAIN_NODES=2
   export NODE_VOLUME_SIZE=500

   # GPU Operator namespace
   export GPU_OPERATOR_NS="gpu-operator"
   ```

3. **Create EKS Cluster**

   Create the EKS cluster without node groups (wait for completion before proceeding):

   ```bash
   eksctl create cluster \
     --name "${CLUSTER_NAME}" \
     --region "${REGION}" \
     --without-nodegroup \
     --install-nvidia-plugin=false
   ```

   **Get Credentials:**

   > **Note**: Wait for the cluster creation to complete before proceeding to get the credentials

   ```bash
   aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
   ```

   Verify your cluster connection:

   ```bash
   kubectl config get-contexts
   ```

   You should see output indicating your cluster context is active.

4. **Create GPU Node Group**

   ```bash
   eksctl create nodegroup \
     --cluster "${CLUSTER_NAME}" \
     --region "${REGION}" \
     --name "${MAIN_NG}" \
     --node-type "${GPU_INSTANCE_TYPE}" \
     --node-volume-size "${NODE_VOLUME_SIZE}" \
     --nodes "${MAIN_NODES}" \
     --node-labels role=gpu-main
   ```

   Verify the nodes are ready:

   ```bash
   kubectl get nodes -l role=gpu-main -o wide
   ```

   You should see 2 nodes in Ready status.

## Task 2. Configure NVIDIA NGC API Key

The Enterprise RAG Blueprint requires access to NVIDIA's container registry and model repositories. You'll need an [NGC API key](https://org.ngc.nvidia.com/setup/api-key) to proceed.

1. **Set your NGC API Key**

   Export your NGC API key as an environment variable:

   ```bash
   export NGC_API_KEY="<YOUR_NGC_API_KEY>"
   ```

   > **Important**: Replace `<YOUR_NGC_API_KEY>` with your actual NGC API key from the NVIDIA NGC portal.

## Task 3. Install NVIDIA GPU Operator

The GPU Operator manages the lifecycle of NVIDIA software components needed for GPU workloads.

1. **Add NVIDIA Helm Repository**

   ```bash
   # Add NVIDIA helm repository
   helm repo add nvidia https://nvidia.github.io/gpu-operator
   helm repo update
   ```

2. **Remove Existing NVIDIA Device Plugin**

   ```bash
   # Remove any existing NVIDIA device plugin (if it exists)
   kubectl delete daemonset nvidia-device-plugin-daemonset -n kube-system --ignore-not-found=true
   ```

3. **Install GPU Operator**

   ```bash
   # Install GPU Operator
   helm upgrade -i gpu-operator nvidia/gpu-operator \
     -n "${GPU_OPERATOR_NS}" --create-namespace \
     --set driver.enabled=false \
     --set toolkit.version=v1.14.3-ubi8
   ```

4. **Verify GPU Allocation**

   Wait for the GPU Operator to be ready, then verify GPU resources are available:

   ```bash
   # Check GPU Operator pods
   kubectl get pods -n gpu-operator

   # Verify GPU allocation on nodes
   kubectl get nodes -l role=gpu-main -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu
   ```

   You should see 8 total GPUs available (4 per g5.12xlarge instance × 2 instances).

## Task 4. Deploy Storage Class

Deploy a local path provisioner for persistent storage needs.

1. **Install Local Path Provisioner**

   ```bash
   kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
   ```

2. **Verify Installation**

   ```bash
   kubectl get pods -n local-path-storage
   ```

3. **Set as Default Storage Class**

   ```bash
   kubectl get storageclass
   kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
   ```

## Task 5. Deploy Enterprise RAG Blueprint

Now you'll deploy the complete Enterprise RAG Blueprint using the optimized configuration.

1. **Create the Custom Values File**

   The `custom-values.yaml` file is already provided in your workshop directory. Verify its contents:

   ```bash
   ls -la custom-values.yaml
   cat custom-values.yaml | head -20
   ```

   This file contains optimized configurations for:
   - GPU resource allocation
   - Model endpoints and configurations
   - Service networking
   - Storage settings

2. **Deploy the RAG Blueprint**

   Deploy the Helm chart with your NGC API key and custom configuration:

   ```bash
   helm upgrade --install rag -n nv-nvidia-blueprint-rag \
     https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-v2.2.0.tgz \
     --username '$oauthtoken' \
     --password "${NGC_API_KEY}" \
     --set imagePullSecret.password=$NGC_API_KEY \
     --set ngcApiSecret.password=$NGC_API_KEY \
     -f custom-values.yaml \
     --create-namespace
   ```

3. **Monitor Deployment Progress**

   The deployment will take 10-15 minutes as it downloads large model artifacts. Monitor the progress:

   ```bash
   # Watch all pods in the namespace
   kubectl get pods -n nv-nvidia-blueprint-rag -w
   ```

   Use `Ctrl+C` to stop watching when all pods are running.

4. **Verify Deployment**

   Ensure all components are successfully running:

   ```bash
   kubectl get all -n nv-nvidia-blueprint-rag
   ```

   You should see pods for:
   - `rag-server` - Main RAG orchestration service
   - `ingestor-server` - Document processing service
   - `nim-llm` - Language model inference
   - `nemoretriever-embedding-ms` - Embedding model
   - `nemoretriever-reranking-ms` - Reranking model
   - `nemoretriever-page-elements-v2` - Document parsing
   - `milvus` - Vector database
   - `rag-redis` - Caching and task management
   - `rag-minio` - Object storage
   - `rag-frontend` - Web interface

## Task 6. Access the RAG Frontend Service

The RAG Blueprint includes a web-based frontend for interacting with the system.

1. **Check Frontend Service**

   ```bash
   kubectl get service rag-frontend -n nv-nvidia-blueprint-rag
   ```

   The service is configured as a NodePort for easy access.

2. **Port Forward to Access Frontend**

   ```bash
   kubectl port-forward service/rag-frontend 3000:3000 -n nv-nvidia-blueprint-rag
   ```

   > **Note**: Keep this terminal open while using the application. You can open a new terminal tab for additional commands.

3. **Access the Frontend**

   Open your web browser and navigate to:
   ```
   http://localhost:3000
   ```

   You should see the RAG Playground interface.

## Task 7. Test the RAG Application

Now you'll test the complete RAG pipeline by uploading documents and asking questions.

1. **Explore the RAG Playground Interface**

   You should see the RAG Playground home page with the main interface:

   ![RAG Playground UI](imgs/RAG-UI.png)

2. **Upload a Document**

   To test the RAG capabilities with your own content:
   
   - Click on the **"New Collection"** tab
   - Add your document and **"Create Collection"** (you can use the [NVIDIA CUDA C Programming Guide](https://docs.nvidia.com/cuda/pdf/CUDA_C_Programming_Guide.pdf) for testing)
   - Wait for the document to be processed and embedded

   ![RAG Playground UI Add document](imgs/RAG-Add-Document.png)

3. **Ask Questions**

   Switch back to the RAG UI and test the RAG capabilities

## Alternative: Interact with RAG via APIs

In addition to using the web interface, you can interact with the Enterprise RAG Blueprint programmatically using the REST APIs. This is ideal for integrating the RAG system into your own applications or for automated workflows.

### API Documentation and Examples

The NVIDIA Enterprise RAG Blueprint provides comprehensive API endpoints for both document ingestion and retrieval operations. You can find detailed examples and usage patterns in these Jupyter notebooks:

1. **Ingestion API Usage**: Learn how to programmatically upload and process documents using the ingestion API
   - [Ingestion API Usage Notebook](https://github.com/NVIDIA-AI-Blueprints/rag/blob/main/notebooks/ingestion_api_usage.ipynb)

2. **Retriever API Usage**: Understand how to query the RAG system and retrieve responses programmatically
   - [Retriever API Usage Notebook](https://github.com/NVIDIA-AI-Blueprints/rag/blob/main/notebooks/retriever_api_usage.ipynb)

For detailed examples and comprehensive API documentation, refer to the [NVIDIA AI Blueprints RAG repository](https://github.com/NVIDIA-AI-Blueprints/rag) which contains the complete source code and additional usage examples.

## Monitor Backend Services

You can monitor the backend services during your interactions with the RAG system to understand performance and troubleshoot any issues:

```bash
# Watch logs from the RAG server
kubectl logs -f deployment/rag-server -n nv-nvidia-blueprint-rag

# Monitor resource usage
kubectl top pods -n nv-nvidia-blueprint-rag
```

## Congratulations!

Congratulations! You've successfully deployed the complete NVIDIA Enterprise RAG Blueprint on Amazon EKS. Your deployment includes:

### Next Steps

Consider exploring these advanced capabilities:

1. **Scale the Deployment**: Increase replica counts for higher throughput
3. **Enable Monitoring**: Deploy Prometheus and Grafana for observability
4. **Production Hardening**: Implement LoadBalancer services and ingress controllers
5. **Multi-modal RAG**: Enable VLM capabilities for image and document understanding

NVIDIA offers enterprise support for production deployments through [NVIDIA AI Enterprise](https://aws.amazon.com/marketplace/seller-profile?id=c568fe05-e33b-411c-b0ab-047218431da9) available on AWS Marketplace.

## Cleanup and Uninstallation

To avoid incurring additional costs, clean up your resources when finished.

### Uninstall RAG Blueprint

```bash
helm uninstall rag -n nv-nvidia-blueprint-rag
kubectl delete namespace nv-nvidia-blueprint-rag
```

### Complete Cluster Cleanup

If you want to completely remove the EKS cluster and all resources:

```bash
# Delete the entire EKS cluster (this will remove all node groups and resources)
eksctl delete cluster --name "${CLUSTER_NAME}" --region "${REGION}"
```

> **Warning**: This will permanently delete all data and resources in the cluster. Make sure to backup any important data before running this command.

## Learn More

For additional information and resources:

- [NVIDIA Enterprise RAG Blueprint](https://build.nvidia.com/nvidia/build-an-enterprise-rag-pipeline)
- [Amazon Elastic Kubernetes Service (EKS)](https://aws.amazon.com/eks/)
- [NVIDIA AI Enterprise](https://aws.amazon.com/marketplace/pp/prodview-ozgjkov6vq3l6)
- [NVIDIA NIMs](https://www.nvidia.com/en-us/ai/)
- [NeMo Retriever Documentation](https://developer.nvidia.com/nemo-retriever)
