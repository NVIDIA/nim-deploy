# CDS on AKS (Single GPU)

NVIDIA Cosmos Dataset Search blueprint on Azure Kubernetes Service with a single H100 GPU.

## Prerequisites

- Azure CLI (logged in), kubectl, helm, jq, openssl, python3
- Azure subscription with H100 quota (`Standard_NC40ads_H100_v5`)
- NGC API Key (from [NGC](https://ngc.nvidia.com/))

## Setup

### 1. Create AKS cluster

```bash
az account set --subscription "<your-subscription>"
az group create --name rg-cds-aks --location eastus2

az aks create \
  --resource-group rg-cds-aks --name aks-cds --location eastus2 \
  --node-count 1 --node-vm-size Standard_D8s_v5 \
  --generate-ssh-keys --network-plugin azure --enable-managed-identity

az aks nodepool add \
  --resource-group rg-cds-aks --cluster-name aks-cds \
  --name gpupool --node-count 1 \
  --node-vm-size Standard_NC40ads_H100_v5 \
  --labels hardware=gpu --node-osdisk-size 512

az aks get-credentials --resource-group rg-cds-aks --name aks-cds --overwrite-existing
```

### 2. Install GPU Operator

```bash
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update
helm install gpu-operator nvidia/gpu-operator \
  -n gpu-operator --create-namespace \
  --set driver.enabled=false \
  --set toolkit.enabled=true

# Verify (~2-3 min)
kubectl get nodes -o json | jq '.items[].status.allocatable["nvidia.com/gpu"]'
```

### 3. Set environment variables

```bash
export NGC_API_KEY="<your-key>"
export RESOURCE_GROUP="rg-cds-aks"
export LOCATION="eastus2"
export STORAGE_ACCOUNT_NAME="cdsstorage$(date +%s | tail -c 8)"
```

> **Re-deploying?** If `.storage-config` exists from a prior run, `storage_up.sh`
> will reuse the same storage account automatically. Do **not** re-export
> `STORAGE_ACCOUNT_NAME` with a new value — Milvus etcd metadata points to
> the original account.

### 4. Deploy CDS

From the repo root:

```bash
cd cloud-service-providers/azure/blueprints/cds-blueprint-aks

./storage_up.sh
./k8s_up.sh
```

`k8s_up.sh` calls `configuration.sh` and `secrets.sh` automatically.
Cosmos-embed model download takes 15-30 min on first run.

Both scripts are idempotent — safe to re-run after a failure or to
update configuration.

### 5. Access

| Service | URL |
|---------|-----|
| **UI** | `http://<ingress-ip>/cosmos-dataset-search` |
| **API** | `http://<ingress-ip>/api/health` |
| **API docs** | `http://<ingress-ip>/api/docs` |

## Usage

```bash
./create_collection.sh my-videos

./ingest_custom_videos.sh <collection-id> "https://example.com/video.mp4"
./ingest_custom_videos.sh <collection-id> /path/to/local/video.mp4

./search.sh <collection-id> "explosion"
```

## Cost control

```bash
# Stop GPU billing (keep cluster)
az aks nodepool scale -g rg-cds-aks --cluster-name aks-cds -n gpupool --node-count 0

# Scale back up
az aks nodepool scale -g rg-cds-aks --cluster-name aks-cds -n gpupool --node-count 1
```

## Teardown

```bash
./teardown/shutdown_sequence.sh

# Or delete the entire resource group
az group delete -n rg-cds-aks --yes
```

## Production scaling

- **Dedicated GPUs:** set `nvidia.com/gpu: 1` in overrides, remove `NVIDIA_VISIBLE_DEVICES`, scale GPU pool.
- **Distributed Milvus:** switch from standalone to distributed mode with Kafka. See upstream `milvus-values.yaml`.
- **TLS:** set `global.ingress.scheme: https` in `values.yaml`, add real certificates via cert-manager or Azure Application Gateway.

## Notes

**UI video playback:** the CDS UI loads video files fully before playing.
Short clips (under ~15 MB) play instantly; longer videos take a moment.
This is a characteristic of the upstream UI, not this deployment.

**GPU Operator on AKS:** fresh clusters on K8s 1.33+ require
`toolkit.enabled=true` in the GPU Operator install.
