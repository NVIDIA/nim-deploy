# NVIDIA NIM Deployment on Oracle Kubernetes Engine (OKE)

This guide provides step-by-step instructions for deploying NVIDIA NIM (NVIDIA Inference Microservices) on Oracle Cloud Infrastructure (OCI) using Oracle Kubernetes Engine (OKE) and A100 GPUs.

---

## 📋 Prerequisites

- An active OCI account  
- OCI CLI installed and configured  
- Proper IAM policies (ContainerEngine, Compute, VCNs, Subnets, Secrets, InstancePools)  
- NVIDIA NGC API key (from [NGC](https://ngc.nvidia.com))  
- Helm installed on your local machine  
- Access to the [`nim-deploy`](https://github.com/NVIDIA/nim-deploy) GitHub repo  

---

## 🧱 Infrastructure Setup

### 1. Create a Virtual Cloud Network (VCN)

- Public Subnet: For OKE worker nodes  
- Private Subnet (optional): For internal services  
- NAT Gateway or Internet Gateway (if using public IPs)  
- Ensure ports `443` and `8000` are open in your NSG or security list (for testing)

---

### 2. Create a NAT Gateway (Recommended)

```bash
oci network route-rule add --route-table-id <ROUTE_TABLE_OCID> \
  --destination 0.0.0.0/0 \
  --network-entity-id <NAT_GATEWAY_OCID>
```

---

### 3. Create the OKE Cluster

```bash
oci ce cluster create \
  --name NIM-OKE-Cluster \
  --compartment-id <COMPARTMENT_OCID> \
  --vcn-id <VCN_OCID> \
  --kubernetes-version "v1.32.1" \
  --subnet-ids '["<SUBNET_OCID>"]'
```

---

### 4. Add Node Pool (A100)

```bash
oci ce node-pool create \
  --cluster-id <CLUSTER_OCID> \
  --name NIM-GPU-Pool \
  --node-shape BM.GPU.A100-v2.8 \
  --node-config-details file://node-config.json
```

#### Sample `node-config.json`:

```json
{
  "placementConfigs": [{
    "availabilityDomain": "Uocm:US-ASHBURN-AD-1",
    "subnetId": "<SUBNET_OCID>"
  }],
  "size": 1
}
```

---

## 🔐 Create Secret for NGC API Key

```bash
kubectl create namespace nim

kubectl create secret generic ngc-api -n nim \
  --from-literal=NGC_API_KEY=<your-ngc-api-key>
```

---

## 🚀 Helm Chart Deployment

### 1. Clone the repo

```bash
git clone https://github.com/NVIDIA/nim-deploy.git
cd nim-deploy/helm
```

---

### Option 1: Minimal Inline Install

```bash
export NGC_API_KEY=<your-ngc-api-key>

helm --namespace nim install my-nim nim-llm/ \
  --set model.ngcAPIKey=$NGC_API_KEY \
  --set persistence.enabled=true
```

---

### Option 2: Custom `values.yaml` (Recommended)

#### Create required secrets:

```bash
kubectl -n nim create secret docker-registry registry-secret \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password=$NGC_API_KEY

kubectl -n nim create secret generic ngc-api \
  --from-literal=NGC_API_KEY=$NGC_API_KEY
```

#### Sample `values.yaml`:

```yaml
image:
  repository: nvcr.io/nim/meta/llama3-8b-instruct
  tag: 1.0.0
imagePullSecrets:
  - name: registry-secret
model:
  name: meta/llama3-8b-instruct
  ngcAPISecret: ngc-api
persistence:
  enabled: true
statefulSet:
  enabled: false
resources:
  limits:
    nvidia.com/gpu: 1
```

#### Deploy with values file:

```bash
helm --namespace nim install my-nim nim-llm/ -f ./values.yaml
```

---

## 🧪 Port Forwarding for Local Testing

```bash
kubectl port-forward svc/my-nim-nim-llm -n nim 8000:8000
curl http://localhost:8000/v1/health/ready
```

---

## 🧾 Sample cURL Test (LLaMA)

```bash
curl http://localhost:8000/v1/completions \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta/llama3-8b-instruct",
    "prompt": "Write a haiku about Oracle Cloud.",
    "temperature": 0.7,
    "max_tokens": 100
  }'
```

#### Sample Response:

```json
{
  "id": "cmpl-xyz123",
  "object": "text_completion",
  "created": 1717070000,
  "model": "meta/llama3-8b-instruct",
  "choices": [
    {
      "text": "Cloud drifts over peaks, \nOracle powers the skies — \nData flows like wind.",
      "index": 0,
      "finish_reason": "stop"
    }
  ]
}
```

> ✅ Note: Make sure your deployed NIM supports the model you're querying.

---

## 🧯 Troubleshooting

### Problem: Pod in `CrashLoopBackOff`

```bash
kubectl logs -n nim <pod-name>
```

- Common cause: Invalid NGC API key or no outbound internet access.

---

### Problem: Hanging `curl` / No Response

```bash
kubectl run curl-test -n nim --image=ghcr.io/curl/curlimages/curl:latest \
  -it --rm --restart=Never -- \
  curl https://api.ngc.nvidia.com
```

If this fails, outbound internet is blocked. Set up a NAT Gateway.

---

## ✅ Final Checklist

- [ ] OKE cluster is active  
- [ ] Node pool (A100) is ready  
- [ ] NAT Gateway or outbound access configured  
- [ ] NGC secret is created in the `nim` namespace  
- [ ] Helm deployment is successful  
- [ ] Service responds on port 8000  

---

## 🔗 Resources

- [NVIDIA NIM GitHub](https://github.com/NVIDIA/nim-deploy)  
- [Oracle Cloud Infrastructure Docs](https://docs.oracle.com/en-us/iaas/Content/home.htm)  
- [NVIDIA NGC](https://ngc.nvidia.com)  
