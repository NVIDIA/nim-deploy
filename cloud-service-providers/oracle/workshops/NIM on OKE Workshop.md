# Deploy NVIDIA NIM (Nemotron Super 49B) on Oracle Kubernetes Engine (OKE) Workshop

## Table of Contents

- [Introduction](#introduction)
- [What You Will Learn](#what-you-will-learn)
- [Learn the Components](#learn-the-components)
- [Setup and Requirements](#setup-and-requirements)
- [Task 1. Create OKE Cluster](#task-1-create-oke-cluster)
- [Task 2. Configure Cluster Access](#task-2-configure-cluster-access)
- [Task 3. Set Up NIM Namespace and NGC API Key](#task-3-set-up-nim-namespace-and-ngc-api-key)
- [Task 4. Install Node Feature Discovery (Optional)](#task-4-install-node-feature-discovery-optional)
- [Task 5. Install NVIDIA NIM Operator](#task-5-install-nvidia-nim-operator)
- [Task 6. Deploy Nemotron Super 49B with Helm](#task-6-deploy-nemotron-super-49b-with-helm)
- [Task 7. Monitor and Test the Deployment](#task-7-monitor-and-test-the-deployment)
- [Congratulations!](#congratulations)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)
- [Learn More](#learn-more)

## Introduction

This workshop will guide you through deploying an NVIDIA NIM (NVIDIA Inference Microservices) on **Oracle Kubernetes Engine (OKE)**. You will deploy **Nemotron Super 49B** using the NVIDIA NIM Helm chart, with a full values configuration included in this guide so you can run inference via an OpenAI-compatible API.

NIM provides production-ready, GPU-optimized inference for foundation models. This workshop uses OKE with bare metal GPU nodes and walks you from cluster creation through to testing completions.

This workshop is ideal for:

- **Platform and ML engineers** who want to serve a single NIM (Nemotron Super 49B) on OKE.
- **Teams evaluating OKE** for GPU inference workloads.
- **Users** who prefer a self-contained guide with the Helm values inlined (no separate values file to track).

## What You Will Learn

By the end of this workshop, you will have hands-on experience with:

1. **Creating an OKE cluster** with GPU nodes (BM shape, full node).
2. **Configuring cluster access** and NGC credentials for NIM.
3. **Installing the NVIDIA NIM Operator** and optional Node Feature Discovery.
4. **Deploying Nemotron Super 49B** using Helm with a baked-in values configuration.
5. **Testing the deployment** via health checks and chat completions.

## Learn the Components

### GPUs in Oracle Kubernetes Engine (OKE)

OKE supports bare metal (BM) GPU shapes. Nodes are offered as **full node** configurations (e.g., 8 GPUs per node). This workshop uses one GPU for Nemotron Super 49B on an H100 node (or two GPUs on an A100).

| Shape | GPUs | GPU Memory |
|-------|------|------------|
| BM.GPU.H100.8 | 8x H100 | 640 GB |
| BM.GPU.A100-v2.8 | 8x A100 | 640 GB |

### NVIDIA NIM (NVIDIA Inference Microservices)

[NVIDIA NIMs](https://developer.nvidia.com/nim) are optimized inference microservices for foundation models. They provide:

- Pre-optimized containers for popular models (e.g., Nemotron Super 49B)
- OpenAI-compatible APIs for completions and health checks
- Support for GPU shapes; Nemotron Super 49B runs on 1x H100 or 2x A100

### Nemotron Super 49B

Nemotron Super 49B is a 49B-parameter model suitable for general-purpose chat and instruction following. For this workshop, you deploy it as a single NIM service with persistent storage and a LoadBalancer for external access.

## Setup and Requirements

### What You Need

To complete this workshop, you need:

- **OCI Account** with access to GPU instances (H100 or A100)
- **OCI CLI** installed and configured
- **kubectl** command-line tool
- **Helm 3.x** package manager
- **NVIDIA NGC Account** for an NGC API Key — [Sign up here](https://ngc.nvidia.com/setup/api-key)
- Sufficient OCI quota for GPU bare metal instances

### GPU Requirements

| Model | H100 80GB | A100 80GB |
|-------|-----------|-----------|
| Nemotron Super 49B | 1 | 2 |

Use a single node (e.g., BM.GPU.H100.8 or BM.GPU.A100-v2.8); the NIM pod will request 1 or 2 GPUs as in the values below.

### IAM Policy Requirements

Ensure your user/group has the following OCI permissions:

```
Allow group <GROUP_NAME> to manage instance-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to manage cluster-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to manage virtual-network-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to use subnets in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to manage secret-family in compartment <COMPARTMENT_NAME>
```

## Task 1. Create OKE Cluster

In this task, you'll create an OKE cluster with GPU nodes using the OCI Console Quick Create feature.

1. Navigate to **OCI Console** → **Developer Services** → **Kubernetes Clusters (OKE)**

2. Click **Create cluster** → Select **Quick create** → Click **Submit**

3. Configure the cluster with the following settings:
   - **Name**: `nim-workshop`
   - **Kubernetes API endpoint**: Select **Public endpoint**
   - **Node type**: Select **Managed**
   - **Shape**: Select `BM.GPU.H100.8` or `BM.GPU.A100-v2.8`
   - **Number of nodes**: `1`
   - **Boot volume size**: `500` GB

4. Click **Create cluster**

5. Wait for the cluster to reach **Active** state (approximately 10-15 minutes)

   You can monitor the cluster creation progress in the OCI Console. The cluster will go through several states: Creating → Active.

## Task 2. Configure Cluster Access

In this task, you'll configure kubectl to access your OKE cluster.

1. **Get your cluster OCID** from the OCI Console (click on the cluster name and copy the OCID)

2. **Set environment variables**:

   ```bash
   export CLUSTER_ID="<your-cluster-ocid>"
   export REGION="<your-region>"  # e.g., us-ashburn-1
   ```

3. **Generate kubeconfig**:

   ```bash
   oci ce cluster create-kubeconfig --cluster-id $CLUSTER_ID --region $REGION \
     --file $HOME/.kube/config --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT
   ```

   > **Note**: OCI tokens can expire (e.g., after ~60 minutes). To refresh, run `oci session authenticate` and then re-run the `create-kubeconfig` command above.

4. **Verify cluster access**:

   ```bash
   kubectl get nodes
   ```

   You should see output similar to:

   ```
   NAME            STATUS   ROLES   AGE   VERSION
   10.0.10.xxx     Ready    node    10m   v1.28.2
   ```

5. **Verify GPU availability**:

   ```bash
   kubectl describe nodes | grep -A5 "Allocatable:" | grep gpu
   ```

   Expected output:

   ```
     nvidia.com/gpu:     8
   ```

## Task 3. Set Up NIM Namespace and NGC API Key

In this task, you'll create the `nim` namespace and store your NGC API key so the cluster can pull NIM images.

1. **Create the namespace**:

   ```bash
   kubectl create namespace nim
   ```

   Expected output:

   ```
   namespace/nim created
   ```

2. **Create the NGC image pull secret** (replace `<your-ngc-api-key>` with your key):

   ```bash
   export NGC_API_KEY="<your-ngc-api-key>"
   kubectl create secret docker-registry ngc-registry \
     --docker-server=nvcr.io \
     --docker-username='$oauthtoken' \
     --docker-password=$NGC_API_KEY \
     -n nim
   ```

   Expected output:

   ```
   secret/ngc-registry created
   ```

3. **Create NGC API secret** (used by the NIM chart for model access):

   ```bash
   kubectl create secret generic ngc-api -n nim --from-literal=NGC_API_KEY=$NGC_API_KEY
   ```

   Expected output:

   ```
   secret/ngc-api created
   ```

## Task 4. Install Node Feature Discovery (Optional)

Node Feature Discovery (NFD) labels nodes with hardware capabilities (e.g., GPUs). The NIM Operator can use these labels for scheduling. This step is optional but recommended.

1. **Add the NFD Helm repository**:

   ```bash
   helm repo add nfd https://kubernetes-sigs.github.io/node-feature-discovery/charts
   helm repo update
   ```

2. **Install NFD**:

   ```bash
   helm install nfd nfd/node-feature-discovery --namespace kube-system
   ```

3. **Verify NFD pods**:

   ```bash
   kubectl get pods -n kube-system | grep nfd
   ```

   Expected output (abbreviated):

   ```
   nfd-master-xxx    1/1   Running   0   xxm
   nfd-worker-xxx    1/1   Running   0   xxm
   ```

## Task 5. Install NVIDIA NIM Operator

In this task, you'll install the NVIDIA NIM Operator, which manages NIM custom resources in the cluster.

1. **Add the NVIDIA Helm repository**:

   ```bash
   helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
   helm repo update
   ```

2. **Install the NIM Operator** (requires NGC auth; use the same profile as for kubectl):

   ```bash
   helm install --namespace nim nvidia-nim-operator nvidia/k8s-nim-operator
   ```

   Expected output (abbreviated):

   ```
   NAME: nvidia-nim-operator
   NAMESPACE: nim
   STATUS: deployed
   ```

3. **Verify the operator**:

   ```bash
   kubectl get pods -n nim -l app.kubernetes.io/instance=nvidia-nim-operator
   ```

   The operator pod should be `Running`.

## Task 6. Deploy Nemotron Super 49B with Helm

In this task, you'll deploy Nemotron Super 49B using the `nim-llm` Helm chart. The values are **baked into this guide** so you don't need a separate values file.

1. **Create a values file** from the configuration below. Copy the following YAML to `nemotron-super-49b-values.yaml`:

   ```yaml
   # Nemotron Super 49B - NIM on OKE (baked into workshop)
   # Use 1 GPU for H100; for A100 use 2 GPUs (see resources section)

   image:
     repository: nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1
     tag: "1.8.2"
     pullPolicy: IfNotPresent

   imagePullSecrets:
     - name: ngc-registry

   model:
     name: nvidia/llama-3.3-nemotron-super-49b-v1
     ngcAPISecret: ngc-api

   persistence:
     enabled: true
     size: 100Gi
     storageClass: "oci-bv"
     accessMode: ReadWriteOnce

   statefulSet:
     enabled: false

   resources:
     limits:
       nvidia.com/gpu: 1   # Use 2 for A100
       memory: "80Gi"
       cpu: "12"
     requests:
       nvidia.com/gpu: 1   # Use 2 for A100
       memory: "64Gi"
       cpu: "8"

   env:
     - name: CONTEXT_WINDOW_SIZE
       value: "4096"
     - name: MAX_TOKENS
       value: "4096"
     - name: NIM_RELAX_MEM_CONSTRAINTS
       value: "1"

   probes:
     startup:
       enabled: true
       httpGet:
         path: /v1/health/ready
         port: 8000
       failureThreshold: 360
       initialDelaySeconds: 480
       periodSeconds: 30
     liveness:
       enabled: true
       httpGet:
         path: /v1/health/live
         port: 8000
       failureThreshold: 3
       initialDelaySeconds: 120
       periodSeconds: 30
     readiness:
       enabled: true
       httpGet:
         path: /v1/health/ready
         port: 8000
       failureThreshold: 3
       initialDelaySeconds: 120
       periodSeconds: 30

   service:
     type: LoadBalancer
     port: 8000

   affinity:
     nodeAffinity:
       requiredDuringSchedulingIgnoredDuringExecution:
         nodeSelectorTerms:
           - matchExpressions:
               - key: nvidia.com/gpu.present
                 operator: In
                 values:
                   - "true"
   ```

   > **Note**: For **A100** nodes, set `nvidia.com/gpu` to `2` in both `resources.limits` and `resources.requests` in the values above. Ensure your cluster has a default StorageClass or that `oci-bv` exists; adjust `persistence.storageClass` if needed.

2. **Install the NIM release**:

   ```bash
   helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
   helm repo update
   helm install --namespace nim nemotron-super-49b nvidia/nim-llm -f nemotron-super-49b-values.yaml
   ```

   Expected output (abbreviated):

   ```
   NAME: nemotron-super-49b
   NAMESPACE: nim
   STATUS: deployed
   ```

3. **Wait for the pod** to become ready (model download and startup can take 10-20 minutes):

   ```bash
   kubectl get pods -n nim -l app.kubernetes.io/instance=nemotron-super-49b -w
   ```

   Leave when the pod shows `Running` and `1/1` Ready. Press `Ctrl+C` to exit the watch.

## Task 7. Monitor and Test the Deployment

In this task, you'll verify the service and run a completion request.

1. **Check the LoadBalancer service**:

   ```bash
   kubectl get svc -n nim
   ```

   Find the service named `nemotron-super-49b` (or similar) with type `LoadBalancer` and note its `EXTERNAL-IP`. Wait until an external IP is assigned.

2. **Test the health endpoint** (replace `<external-ip>` with the service IP):

   ```bash
   curl http://<external-ip>:8000/v1/health/ready
   ```

   Expected output:

   ```json
   {"status":"ready"}
   ```

3. **Test a chat completion**:

   ```bash
   curl -X POST http://<external-ip>:8000/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{
       "messages": [
         {"role": "system", "content": "You are a helpful assistant."},
         {"role": "user", "content": "What is NVIDIA NIM in one sentence?"}
       ],
       "model": "nvidia/llama-3.3-nemotron-super-49b-v1",
       "max_tokens": 150
     }'
   ```

   Expected output: JSON with `choices[].message.content` containing the model's response.

**Expected output (summary):** A successful health check and a JSON completion response. The `model` in the request must match the NIM model name in your values (e.g., `nvidia/llama-3.3-nemotron-super-49b-v1`).

## Congratulations!

You have deployed Nemotron Super 49B as an NVIDIA NIM on OKE and verified inference. You can now:

- Call the LoadBalancer IP on port 8000 for OpenAI-compatible completions
- Integrate this endpoint into your applications
- Scale or upgrade the deployment by editing the Helm release or values and upgrading

## Troubleshooting

| Issue | Action |
|-------|--------|
| Pod stays in `ContainerCreating` or `Pending` | Check `kubectl describe pod -n nim -l app.kubernetes.io/instance=nemotron-super-49b` for image pull or GPU scheduling issues; verify NGC secret and node GPU capacity. |
| `Insufficient nvidia.com/gpu` | Ensure the node has allocatable GPUs (e.g., run `kubectl describe nodes` and check the Allocatable section); ensure the values request no more GPUs than available. |
| LoadBalancer EXTERNAL-IP `<pending>` | Wait a few minutes; check cloud provider load balancer limits and firewall. |
| Health check never ready | Increase `probes.startup.failureThreshold` and `initialDelaySeconds`; check pod logs with `kubectl logs -n nim -l app.kubernetes.io/instance=nemotron-super-49b -f`. |
| 401 or image pull errors | Verify `ngc-registry` and `ngc-api` secrets in `nim` namespace and that `NGC_API_KEY` is valid. |

---

## Cleanup

Clean up resources when done.

1. **Uninstall the NIM release**:

   ```bash
   helm uninstall nemotron-super-49b -n nim
   ```

2. **Uninstall the NIM Operator** (optional):

   ```bash
   helm uninstall nvidia-nim-operator -n nim
   ```

3. **Uninstall NFD** (if you installed it):

   ```bash
   helm uninstall nfd -n kube-system
   ```

4. **Delete the OKE cluster** (optional — via OCI Console):

   Navigate to **OCI Console** → **Developer Services** → **Kubernetes Clusters** → Select your cluster → **Delete**

## Learn More

- [NIM Deployment on OKE (Full Guide)](../oke/README.md) — Detailed OKE setup including VCN, instance configuration, cluster network, proxy, and verification
- [NVIDIA NIMs](https://developer.nvidia.com/nim)
- [NVIDIA NIM Documentation](https://docs.nvidia.com/nim/)
- [NVIDIA NGC](https://ngc.nvidia.com)
- [Oracle Kubernetes Engine (OKE)](https://www.oracle.com/cloud/cloud-native/container-engine-kubernetes/)
