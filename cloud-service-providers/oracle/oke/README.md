# NVIDIA NIM Deployment on Oracle Kubernetes Engine (OKE)

This guide provides step-by-step instructions for deploying NVIDIA NIM (NVIDIA Inference Microservices) on Oracle Cloud Infrastructure (OCI) using Oracle Kubernetes Engine (OKE) and GPU instances. NIM allows you to easily deploy and serve AI models with production-ready APIs, scalability, and GPU optimization.

## Overview

This guide gives you what you need to deploy **any** [NVIDIA NIM](https://developer.nvidia.com/nim) on OKE. There are two deployment paths:

| Method | When to use | Section |
|--------|-------------|---------|
| **Helm chart** | NIM has an official Helm chart on NGC (LLMs, VLMs, embedding/rerank models, etc.) | [Option A: Helm Charts](#option-a-nims-with-helm-charts) |
| **Kubernetes manifests** | NIM has no Helm chart | [Option B: Kubernetes Manifests](#option-b-kubernetes-manifests) |

**Finding NIMs:** Browse the [NGC NIM catalog](https://catalog.ngc.nvidia.com/orgs/nim/containers) for container images and tags. To check if a NIM has a Helm chart, run `helm search repo nvidia-nim/` after adding the repo. See [NIM documentation](https://docs.nvidia.com/nim/).

## Prerequisites

Before starting the deployment process, ensure you have the following:

- **Oracle Cloud Infrastructure (OCI) Account** with appropriate permissions
- **OCI CLI** installed and configured
- **NVIDIA NGC Account** for an **NGC API Key** to pull container images. Sign up at [ngc.nvidia.com](https://ngc.nvidia.com/setup/api-key)
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

You can assign these permissions through OCI IAM policies or by using predefined roles like "OKE Cluster Administrator" combined with "Network Administrator" and "Compute Instance Administrator" for your compartment.

## Hardware Requirements

- **GPU**: One or more nodes with a GPU shape suitable for your model size. See [GPU Compatibility](#gpu-compatibility) for recommended shapes (e.g., A10/L40S for 8B, A100/H100 for 70B).
- **Boot volume**: Minimum 100 GB.

---

## Infrastructure Setup

This section covers the steps to prepare your OCI infrastructure for running NIM.

### Console Quick Create (Recommended)

The fastest way — auto-provisions networking.

1. Go to **OCI Console** → **Developer Services** → **Kubernetes Clusters (OKE)**
2. Click **Create cluster** → Select **Quick create** → **Submit**
3. Configure:
   - Name: `gpu-cluster`
   - Kubernetes API endpoint: **Public endpoint**
   - Shape: Select GPU shape based on [Hardware Requirements](#hardware-requirements)
   - Nodes: `1` (or more if deploying multiple NIMs)
   - Boot volume: `100` GB minimum
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

If you specified a 100 GB boot volume, you should see adequate ephemeral storage. If you see ~35 GB, expand the boot volume (see step 2). Otherwise, skip to step 3.

#### 2. Expand Boot Volume (if needed)

**Option A: Via kubectl (no SSH required)**

```bash
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl run growfs --rm -it --restart=Never --privileged \
  --overrides='{"spec":{"hostPID":true,"nodeName":"'$NODE_NAME'"}}' \
  --image=docker.io/library/oraclelinux:8 -- nsenter -t 1 -m -u -i -n /usr/libexec/oci-growfs -y
kubectl run restart-kubelet --rm -it --restart=Never --privileged \
  --overrides='{"spec":{"hostPID":true,"nodeName":"'$NODE_NAME'"}}' \
  --image=docker.io/library/oraclelinux:8 -- nsenter -t 1 -m -u -i -n systemctl restart kubelet
```

**Option B: Via SSH (if you have node access)**

```bash
sudo /usr/libexec/oci-growfs -y
sudo systemctl restart kubelet
```

#### 3. Set Up Cluster

```bash
# Remove GPU taints so NIM pods can schedule
kubectl taint nodes --all nvidia.com/gpu:NoSchedule- 2>/dev/null || true

# Verify GPU resources
kubectl describe nodes | grep -A5 "Allocatable:" | grep gpu
```

> **OCI token (if using security_token):** The OCI security token has a maximum lifetime of 60 minutes. To refresh: run `oci session authenticate` (or re-login), then recreate the kubeconfig with the same `oci ce cluster create-kubeconfig` command from [Console Quick Create](#console-quick-create-recommended).

---

## Set Up the NIM Namespace and NGC API Key

Create a dedicated namespace for NIM and store your NGC API key as a Kubernetes secret:

```bash
# Create namespace
kubectl create namespace nim
```

**Expected Output:**
```
namespace/nim created
```

```bash
# Set your NGC API key
export NGC_API_KEY="<your-ngc-api-key>"

# Create a secret for pulling images from NGC
kubectl create secret docker-registry ngc-registry \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password=$NGC_API_KEY \
  -n nim

# Required for LLM and VLM charts that download model assets from NGC
kubectl create secret generic ngc-api -n nim --from-literal=NGC_API_KEY=$NGC_API_KEY
```

**Expected Output:**
```
secret/ngc-registry created
secret/ngc-api created
```

This isolates your NIM deployment from other applications in the cluster. The `ngc-registry` secret is used to pull container images from NGC; the `ngc-api` secret is used by Helm charts (e.g., nim-llm, nim-vlm) to download model assets. Use the same NGC API key for both.

## Deploy NIMs on OKE

Pick **Option A** if your NIM has a Helm chart on NGC, or **Option B** if it doesn't.

---

### Option A: NIMs with Helm Charts

NVIDIA publishes Helm charts for many NIMs on NGC. Each chart handles health probes, services, and optional persistence. The examples below use `--set` flags for quick deployment. For more control, you can put the same settings into a `values.yaml` file and install with `helm install ... -f values.yaml` instead.

The two main charts are **`nim-llm`** (for LLMs) and **`nim-vlm`** (for VLMs), both under `https://helm.ngc.nvidia.com/nim`. Additional charts exist for embedding, reranking, and other NIM types — run `helm search repo nvidia-nim/` after adding the repo to see what's available.

#### Add the Helm Repo

```bash
helm repo add nvidia-nim https://helm.ngc.nvidia.com/nim
helm repo update
```

#### Deploy an LLM NIM (example: Nemotron Super 49B)

```bash
helm --namespace nim install nemotron-super nvidia-nim/nim-llm \
  --set image.repository=nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1 \
  --set image.tag=latest \
  --set model.name=nvidia/llama-3.3-nemotron-super-49b-v1 \
  --set imagePullSecrets[0].name=ngc-registry \
  --set model.ngcAPISecret=ngc-api \
  --set resources.limits.nvidia\\.com/gpu=1 \
  --set persistence.enabled=false \
  --set service.type=LoadBalancer
```

**Expected Output:**
```
NAME: nemotron-super
NAMESPACE: nim
STATUS: deployed
```

Wait for the pod to become ready (model download can take 5-10 minutes):

```bash
kubectl get pods -n nim -w
```

> **Deploying a different LLM?** Change `image.repository`, `image.tag`, and `model.name`. For larger models (70B+), increase `resources.limits.nvidia\\.com/gpu`. To persist the model cache across restarts, add `--set persistence.enabled=true --set persistence.storageClass=oci-bv --set persistence.size=50Gi`.

> **Want more control?** Use a values file instead of `--set` flags: `helm install nemotron-super nvidia-nim/nim-llm -n nim -f values.yaml`. See [Appendix: Example Values File](#appendix-example-values-file) for a full `nim-llm` values file for Nemotron Super 49B.

#### Deploy a VLM NIM (example: NemoRetriever Parse)

```bash
helm --namespace nim install nemoretriever-parse nvidia-nim/nim-vlm \
  --set image.repository=nvcr.io/nim/nvidia/nemoretriever-parse \
  --set image.tag=1.2.0 \
  --set imagePullSecrets[0].name=ngc-registry \
  --set nim.ngcAPISecret=ngc-api \
  --set resources.limits.nvidia\\.com/gpu=1 \
  --set persistence.enabled=false \
  --set service.type=LoadBalancer
```

**Expected Output:**
```
NAME: nemoretriever-parse
NAMESPACE: nim
STATUS: deployed
```

#### Other Helm Charts

The same `--set` pattern works for any NIM that has a Helm chart (embedding, reranking, etc.). Use `helm search repo nvidia-nim/` to discover available charts, and check the [NGC NIM catalog](https://catalog.ngc.nvidia.com/orgs/nim/containers) for image names and tags.

---

### Option B: Kubernetes Manifests

Use this option when your NIM doesn't have a Helm chart. Deploy with a **Deployment** and **Service** using the same `nim` namespace and NGC pull secret (`ngc-registry`).

1. **Image:** Get the correct image and tag from the [NGC NIM catalog](https://catalog.ngc.nvidia.com/orgs/nim/containers) and the image's documentation (GPU vs CPU, memory).
2. **Manifest:** Use `imagePullSecrets: [{ name: ngc-registry }]`, the NIM image, appropriate `resources` (e.g., `nvidia.com/gpu: 1`), and health probes on the port the NIM serves (often `8000`). Expose with a Service (`ClusterIP` or `LoadBalancer`).
3. **Env and storage:** Some NIMs need `NGC_API_KEY` or a volume for cache; see the image's NGC page.

Example pattern (replace `<nim-image>` and `<tag>`):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-nim
  namespace: nim
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-nim
  template:
    metadata:
      labels:
        app: my-nim
    spec:
      imagePullSecrets:
        - name: ngc-registry
      containers:
        - name: my-nim
          image: nvcr.io/nim/nvidia/<nim-image>:<tag>
          ports:
            - containerPort: 8000
          resources:
            limits:
              nvidia.com/gpu: 1
          readinessProbe:
            httpGet:
              path: /v1/health/ready
              port: 8000
            initialDelaySeconds: 60
            periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: my-nim
  namespace: nim
spec:
  selector:
    app: my-nim
  ports:
    - port: 8000
      targetPort: 8000
  type: LoadBalancer
```

Apply with `kubectl apply -f <file>.yaml`. For exact image names and API usage, see [NIM on NGC](https://catalog.ngc.nvidia.com/orgs/nim/containers) and [NIM documentation](https://docs.nvidia.com/nim/).

## Monitor Deployment Status

Monitor pods and services to verify your NIMs are running:

```bash
kubectl get pods -n nim
```

**Expected Output (initial state):**
```
NAME                            READY   STATUS              RESTARTS   AGE
nemotron-super-nim-llm-0        0/1     ContainerCreating   0          2m
nemoretriever-parse-nim-vlm-0   0/1     ContainerCreating   0          2m
```

**Expected Output (after model download):**
```
NAME                            READY   STATUS    RESTARTS   AGE
nemotron-super-nim-llm-0        1/1     Running   0          10m
nemoretriever-parse-nim-vlm-0   1/1     Running   0          5m
```

```bash
kubectl get svc -n nim
```

**Expected Output:**
```
NAME                              TYPE           CLUSTER-IP      EXTERNAL-IP       PORT(S)          AGE
nemotron-super-nim-llm            LoadBalancer   10.96.178.84    <external-ip>     8000:30450/TCP   10m
nemoretriever-parse-nim-vlm       LoadBalancer   10.96.143.91    <external-ip>     8000:31220/TCP   10m
```

Pods may initially show `ContainerCreating` while pulling the image, then take several minutes to download model weights and start the inference server.

## Test the Model

Get the external IP of your NIM service:

```bash
kubectl get svc -n nim nemotron-super-nim-llm
```

Once the `EXTERNAL-IP` is assigned (may take 1-2 minutes), test the service:

```bash
# Health check
curl -s http://<external-ip>:8000/v1/health/ready
```

**Expected Output:**
```json
{"object":"health.response","message":"Service is ready."}
```

```bash
# Chat completion
curl -s http://<external-ip>:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nvidia/llama-3.3-nemotron-super-49b-v1",
    "messages": [{"role": "user", "content": "Hello, tell me briefly about NVIDIA."}],
    "max_tokens": 150
  }'
```

**Expected Output (abbreviated):**
```json
{
  "id": "chatcmpl-abc123",
  "object": "chat.completion",
  "model": "nvidia/llama-3.3-nemotron-super-49b-v1",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "NVIDIA is a leading technology company specializing in GPUs and AI computing..."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 15,
    "completion_tokens": 50,
    "total_tokens": 65
  }
}
```

## Conclusion

You now have NVIDIA NIMs deployed on OKE. Each NIM exposes an OpenAI-compatible API on port 8000, making it easy to integrate with applications.

To manage your deployments:

```bash
# List all Helm releases
helm list -n nim

# Uninstall a NIM
helm uninstall <release-name> -n nim

# Upgrade a NIM (e.g., change image tag)
helm upgrade <release-name> nvidia-nim/<chart> --namespace nim --set image.tag=<new-tag> --reuse-values
```

Remember to regularly check your OCI authentication status if you encounter connection issues, as session tokens expire after a few hours.

## Infrastructure Creation Summary

In this guide, infrastructure is set up via **Console Quick Create** (recommended): create an OKE cluster with a GPU node pool, configure kubectl, then run [Pre-Deployment Setup](#pre-deployment-setup) (storage, taints). For scripted or CLI-based deployment, use [Appendix: CLI Deployment](#appendix-cli-deployment). After the cluster is ready, you deploy NIM (namespace, NGC secret, then Helm or Kubernetes manifests) and configure persistent storage for model weights as needed.

---

## Deployment Checklist

Ensure the following are complete before proceeding with inference:

- [ ] **OKE cluster** is active and accessible  
- [ ] **GPU node pool** (e.g., A100, L40S) is ready and healthy  
- [ ] **NAT Gateway** or other outbound internet access is configured  
- [ ] **NGC secrets** are created in the `nim` namespace (`ngc-registry`, `ngc-api`)  
- [ ] **Helm chart** deployed successfully (`helm list -n nim`)  
- [ ] **NIM service** is reachable on port 8000

### Verification Steps

Use these commands to verify your deployment is correctly configured:

```bash
# Check if your OKE cluster is accessible
kubectl get nodes
```

```bash
# Verify GPU node labels are detected
kubectl describe nodes | grep nvidia.com/gpu
```

```bash
# Confirm NGC secrets exist (ngc-registry for image pull, ngc-api for LLM/VLM model download)
kubectl get secret -n nim ngc-registry ngc-api
```

```bash
# Verify Helm chart is installed
helm list -n nim
```

```bash
# Check NIM pod health
kubectl get pods -n nim
```

```bash
# Test via LoadBalancer
EXTERNAL_IP=$(kubectl get svc -n nim nemotron-super-nim-llm -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -s http://${EXTERNAL_IP}:8000/v1/health/ready
```

These verification steps should all return successful responses to confirm your deployment is ready.

---

## GPU Compatibility

### Recommended GPU Shapes

| Model Size | Recommended Shapes |
|------------|--------------------|
| 8B         | `BM.GPU.A10G.2`, `BM.GPU.L40.2` |
| 13B        | `BM.GPU.L40.2`, `BM.GPU.A100-v2.8` |
| 30B        | `BM.GPU.A100-v2.8`, `BM.GPU.H100.8` |
| 70B+       | `BM.GPU.H100.8`, `BM.GPU.H200.8` |

### Supported OCI GPUs for NIM

| GPU Model    | Memory   | Architecture | NIM Compatibility | Best For                       |
|--------------|----------|--------------|-------------------|--------------------------------|
| H200         | 141 GB   | Hopper       | Excellent       | Max throughput, large models   |
| H100         | 80 GB    | Hopper       | Excellent       | 30B-70B models, production use |
| A100         | 80 GB    | Ampere       | Excellent       | Most models, stable baseline   |
| L40S         | 48 GB    | Lovelace     | Good            | Mid-size models (7B-30B)       |
| A10G         | 24 GB    | Ampere       | Limited         | Small models (7B-13B)          |

---

## Troubleshooting

This section outlines the most common issues you might encounter when deploying or running NIM on OKE, along with actionable steps to resolve them.

### Common Problems & Fixes

#### Pod in CrashLoopBackOff

```bash
kubectl logs -n nim <pod-name>
```

**Expected Output (for NGC API key issues):**
```
Error: Failed to download model files: Authentication failed. Please check your NGC API key.
```

**Possible causes:**

- Invalid NGC API key
- No outbound internet access
- Insufficient GPU resources

---

#### Hanging curl / No Response

```bash
kubectl run curl-test -n nim --image=ghcr.io/curl/curlimages/curl:latest \
  -it --rm --restart=Never -- \
  curl https://api.ngc.nvidia.com
```

**Expected Output (successful connection):**
```
<html>
<head><title>301 Moved Permanently</title></head>
<body>
<center><h1>301 Moved Permanently</h1></center>
<hr><center>nginx</center>
</body>
</html>
```

**If this fails:** Outbound internet is blocked. Set up a NAT Gateway or configure proxy settings.

---

#### GPU Not Detected

```bash
kubectl describe nodes | grep nvidia.com/gpu
```

**Expected Output:**
```
                    nvidia.com/gpu:             8
                    nvidia.com/gpu.memory:      81920M
                    nvidia.com/gpu.product:     A100-SXM4-80GB
```

**Possible causes:**

- GPU drivers not properly installed on nodes
- Incorrect GPU shape configuration

---

#### Authentication Issues

```bash
# Method 1: Session authentication
oci session authenticate
```

**Expected Output:**
```
Enter a password or web browser will be opened to https://login.us-ashburn-1.oraclecloud.com/...
```

```bash
# Method 2: Validate existing session
oci session validate --profile oci
```

**Expected Output (valid session):**
```
Session is valid
```

**Expected Output (expired session):**
```
Session is invalid or expired
```

Session tokens typically expire after a few hours. Refresh if needed.

---

#### Internet Connectivity Problems

```bash
# Test general internet connectivity from within the cluster
kubectl run test-connectivity --image=alpine -n nim --rm -it -- sh -c "apk add curl && curl -I https://ngc.nvidia.com"
```

**Expected Output:**
```
HTTP/1.1 200 OK
Date: Mon, 01 Jun 2023 12:34:56 GMT
Server: nginx
Content-Type: text/html; charset=UTF-8
Connection: keep-alive
Cache-Control: no-cache
```

**Troubleshooting steps:**

1. **If DNS resolution fails:** Check DNS server configuration in the cluster
   ```bash
   kubectl run dns-test -n nim --rm -it --image=alpine -- nslookup ngc.nvidia.com
   ```

2. **If a proxy is needed:** Configure HTTP_PROXY and HTTPS_PROXY environment variables in your pod spec
   ```yaml
   env:
   - name: HTTP_PROXY
     value: "http://proxy.example.com:8080"
   - name: HTTPS_PROXY
     value: "http://proxy.example.com:8080"
   - name: NO_PROXY
     value: "localhost,127.0.0.1,10.96.0.0/12,192.168.0.0/16"
   ```

3. **If the NAT Gateway isn't working:** Verify your route table configurations
   ```bash
   oci network route-table get --rt-id <ROUTE_TABLE_OCID>
   ```

4. **For security group issues:** Ensure outbound traffic is allowed on ports 443 and 80
   ```bash
   oci network security-list list --subnet-id <SUBNET_OCID>
   ```

---

## Resources

- [NIM on OKE Workshop](../workshops/NIM%20on%20OKE%20Workshop.md) — hands-on workshop version
- [NVIDIA NIMs](https://developer.nvidia.com/nim)
- [NVIDIA NIM Documentation](https://docs.nvidia.com/nim/)
- [NVIDIA NGC](https://ngc.nvidia.com)
- [Oracle Kubernetes Engine (OKE)](https://www.oracle.com/cloud/cloud-native/container-engine-kubernetes/)

---

## Appendix: CLI Deployment

Use this for automation or scripted deployments when you cannot use [Console Quick Create](#console-quick-create-recommended). Steps: create VCN and networking, create instance configuration, create cluster network with GPU nodes, then configure kubectl.

### 1. Create a Virtual Cloud Network (VCN)

Set up the networking infrastructure: public subnet for OKE worker nodes, NAT Gateway or Internet Gateway for outbound access, and ensure ports `443` and `8000` are open in your NSG or security list for trusted IP ranges. Use restricted CIDR blocks instead of opening to all IPs.

### 2. Create a NAT Gateway (Recommended)

```bash
oci network route-rule add --route-table-id <ROUTE_TABLE_OCID> \
  --destination 0.0.0.0/0 \
  --network-entity-id <NAT_GATEWAY_OCID>
```

### 3. Create an Instance Configuration

Template for your GPU instances (shape, image, network, SSH):

```bash
oci compute-management instance-configuration create \
  --compartment-id <COMPARTMENT_OCID> \
  --instance-details '{
    "instanceType": "compute",
    "launchDetails": {
      "availabilityDomain": "<AVAILABILITY_DOMAIN>",
      "compartmentId": "<COMPARTMENT_OCID>",
      "shape": "BM.GPU.A100-v2.8",
      "sourceDetails": { "sourceType": "image", "imageId": "<IMAGE_OCID>" },
      "metadata": { "ssh_authorized_keys": "<YOUR_SSH_PUBLIC_KEY>" },
      "createVnicDetails": { "subnetId": "<SUBNET_OCID>", "assignPublicIp": true }
    }
  }' \
  --profile OCI
```

### 4. Create the Cluster Network with GPU Nodes

```bash
oci compute-management cluster-network create \
  --compartment-id <COMPARTMENT_OCID> \
  --instance-pools file://instance_pools.json \
  --placement-configuration file://placement_config.json \
  --display-name "A100-Cluster-NIM" \
  --profile OCI
```

Use `instance_pools.json` and `placement_config.json` as in the [RAG Blueprint Appendix](../blueprints/RAG%20Blueprint%20on%20OKE%20Guide.md#appendix-cli-deployment) (same structure: instance configuration OCID, size, availability domain, subnet).

### 5. Configure kubectl

After the cluster is active, get the cluster OCID from the console (or CLI) and run:

```bash
export CLUSTER_ID="<cluster-ocid>"
export REGION="<your-region>"
oci ce cluster create-kubeconfig --cluster-id $CLUSTER_ID --region $REGION \
  --file $HOME/.kube/config --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT
```

Then continue from [Pre-Deployment Setup](#pre-deployment-setup) (verify storage, expand boot volume if needed, remove GPU taints).

---

## Appendix: Example Values File

Below is a full `nim-llm` values file for deploying Nemotron Super 49B on OKE. Save it as `nemotron-super-values.yaml` and install with:

```bash
helm --namespace nim install nemotron-super nvidia-nim/nim-llm -f nemotron-super-values.yaml
```

```yaml
image:
  repository: nvcr.io/nim/nvidia/llama-3.3-nemotron-super-49b-v1
  tag: "latest"
  pullPolicy: IfNotPresent

imagePullSecrets:
  - name: ngc-registry

model:
  name: nvidia/llama-3.3-nemotron-super-49b-v1
  ngcAPISecret: ngc-api
  nimCache: /model-store
  openaiPort: 8000
  jsonLogging: true
  logLevel: INFO

resources:
  limits:
    nvidia.com/gpu: 1

persistence:
  enabled: false
  # To persist model cache across restarts:
  # enabled: true
  # storageClass: "oci-bv"
  # accessMode: ReadWriteOnce
  # size: 50Gi

service:
  type: LoadBalancer
  openaiPort: 8000

statefulSet:
  enabled: true

podSecurityContext:
  runAsUser: 1000
  runAsGroup: 1000
  fsGroup: 1000

tolerations:
  - key: nvidia.com/gpu
    operator: Exists
    effect: NoSchedule

startupProbe:
  enabled: true
  path: /v1/health/ready
  initialDelaySeconds: 40
  periodSeconds: 10
  failureThreshold: 180

livenessProbe:
  enabled: true
  path: /v1/health/live
  initialDelaySeconds: 15
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  enabled: true
  path: /v1/health/ready
  initialDelaySeconds: 15
  periodSeconds: 10
  failureThreshold: 3
```

> **Customizing for other models:** Change `image.repository`, `image.tag`, and `model.name` to match your target NIM. For larger models, increase `resources.limits.nvidia.com/gpu` and enable persistence with a larger `size`. Run `helm show values nvidia-nim/nim-llm` to see all available options.
