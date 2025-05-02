# OCI + OKE Setup for NVIDIA NIM Deployment

This guide walks through provisioning an Oracle Kubernetes Engine (OKE) cluster with GPU support to deploy NVIDIA NIM containers.

---

## Prerequisites

- An active [Oracle Cloud Infrastructure](https://cloud.oracle.com/) (OCI) tenancy
- Proper IAM permissions to create:
  - VCN, subnet, NSG
  - Compute instances (A100 shape)
  - OKE clusters
- Oracle Cloud CLI installed (`oci`)
- `kubectl` and optionally `helm`
- NVIDIA NGC API key

---

## Step 1: Create a Public Subnet with Internet Access

Create a VCN and a public subnet with:
- Route table pointing to Internet Gateway
- DHCP options for DNS resolution
- NSG rule allowing inbound TCP 8000 (for NIM)

Example NSG rule:
```text
Ingress | TCP | 8000 | 0.0.0.0/0 | Allow public access to NIM
```

---

## Step 2: Launch an OKE Cluster with GPU Nodes

1. Go to OCI Console → **Developer Services → Kubernetes Clusters (OKE)**
2. Click **Create Cluster** → **Quick Create** or **Custom Create**
3. Ensure worker nodes use shape:
   - `BM.GPU.A100-v2.8` or similar (A100 GPU)
4. Enable `nvidia.com/gpu` scheduling by installing the NVIDIA device plugin (optional for managed)

---

## Step 3: Configure Kube Access

Get the OKE cluster kubeconfig:
```bash
oci ce cluster create-kubeconfig \
  --cluster-id <your-cluster-ocid> \
  --file $HOME/.kube/config \
  --region <your-region> \
  --token-version 2.0.0
```

Verify access:
```bash
kubectl get nodes
```

You should see at least 1 GPU node in `Ready` state.

---

## Step 4: Verify GPU Availability

```bash
kubectl describe node <gpu-node-name> | grep -i nvidia
```

You should see:
```text
Capacity:
  nvidia.com/gpu:  8
Allocatable:
  nvidia.com/gpu:  8
```

---

## Step 5: Prepare for NIM Deployment

Before applying manifests:
- Create secrets for NGC API key and image pull auth
- Ensure your `nim-deployment.yaml` uses the correct `imagePullSecrets` and `env` keys
- If you're not using a public LoadBalancer, test via `kubectl port-forward`

---

## Cleanup (Optional)

Delete the OKE cluster:
```bash
oci ce cluster delete --cluster-id <your-cluster-ocid>
```

Remove associated node pools and subnets manually via console.

---

## Outcome
You now have an OCI-backed OKE cluster with NVIDIA GPU support, fully ready to deploy `nvcr.io/nim/meta/llama3-8b-instruct` and serve OpenAI-compatible LLM inference.

---

For deployment YAMLs and full instructions, go back to [`setup/`](../setup/README.md).
