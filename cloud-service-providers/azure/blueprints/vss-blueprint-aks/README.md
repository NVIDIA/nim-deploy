# VSS on AKS (Single GPU)

NVIDIA Video Search and Summarization blueprint on Azure Kubernetes Service with a single H100 GPU.

All models share one GPU using low-memory modes:

| Service | Model | Role |
|---------|-------|------|
| nim-llm | Llama 3.1 8B Instruct | LLM (summarization, chat) |
| vss-engine | Cosmos-Reason2-8B | VLM (video captioning) |
| nemo-embedding | llama-3.2-nv-embedqa-1b-v2 | Embedding |
| nemo-rerank | llama-3.2-nv-rerankqa-1b-v2 | Reranking |

## Prerequisites

- Azure CLI (logged in), kubectl, helm, python3, curl
- Azure subscription with H100 quota (`Standard_NC40ads_H100_v5`)
- [NGC API Key](https://ngc.nvidia.com)
- [Hugging Face Token](https://huggingface.co/settings/tokens) — accept the license for [Llama 3.1 8B Instruct](https://huggingface.co/meta-llama/Llama-3.1-8B-Instruct) and [Cosmos-Reason2-8B](https://huggingface.co/nvidia/Cosmos-Reason2-8B)

## Setup

### 1. Set environment variables

```bash
export NGC_API_KEY="<your-key>"
export HF_TOKEN="<your-token>"
export RESOURCE_GROUP="<your-resource-group>"
export LOCATION="<Azure region (e.g.: eastus2)>"
export AKS_CLUSTER_NAME="<your-cluster-name>"
export GPU_VM_SIZE="Standard_NC40ads_H100_v5"               # 80 GB+ VRAM recommended; tested with H100
```

Check your GPU quota:
```bash
az vm list-usage --location $LOCATION -o table | grep NC40
```

### 2. Create AKS cluster

```bash
az account set --subscription "<your-subscription>"
az group create --name $RESOURCE_GROUP --location $LOCATION

az aks create \
  --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --location $LOCATION \
  --node-count 1 --node-vm-size Standard_D8s_v5 \
  --generate-ssh-keys --network-plugin azure --enable-managed-identity

az aks nodepool add \
  --resource-group $RESOURCE_GROUP --cluster-name $AKS_CLUSTER_NAME \
  --name gpupool --node-count 1 \
  --node-vm-size $GPU_VM_SIZE \
  --labels hardware=gpu --node-osdisk-size 512

az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --overwrite-existing
```

> **Do not** add taints to the GPU node pool. Pods with `nvidia.com/gpu: 0`
> (GPU sharing) won't auto-tolerate them.

### 3. Deploy VSS

From the repo root:

```bash
cd cloud-service-providers/azure/blueprints/vss-blueprint-aks
./k8s_up.sh
```

`k8s_up.sh` calls `configuration.sh` and `secrets.sh` automatically, installs
the GPU Operator, and deploys the Helm chart. First run takes 15-30 minutes
(model downloads + VLM compilation).

### 4. Access

```bash
kubectl port-forward svc/vss-service 8100:8000 &
kubectl port-forward svc/vss-service 9100:9000 &

curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8100/health/ready   # should print 200
```

| Service | URL |
|---------|-----|
| **API** | http://localhost:8100 |
| **UI** | http://localhost:9100 |

## Usage

### Summarize a video (on-cluster, recommended)

```bash
./summarize_url_cluster.sh "https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
```

The video is downloaded directly inside the cluster pod and uploaded to VSS
internally — video bytes never leave the AKS network. Only the small JSON
request/response travels through the local port-forward, making this much
faster for large files.

### Summarize a video (local download)

```bash
./summarize_url.sh "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4"
```

Downloads the video locally, uploads through port-forward. Results saved to `summaries/`.

### Customizing prompts

The `/summarize` API accepts three prompts (see `summarize_url.sh`):

- `prompt` — per-chunk VLM caption
- `caption_summarization_prompt` — how chunk captions are structured
- `summary_aggregation_prompt` — how the final summary is aggregated

## Cost control

```bash
# Stop GPU billing (keep cluster)
az aks nodepool scale -g $RESOURCE_GROUP --cluster-name $AKS_CLUSTER_NAME -n gpupool --node-count 0

# Scale back up (~5-10 min, PVCs persist so model cache is retained)
az aks nodepool scale -g $RESOURCE_GROUP --cluster-name $AKS_CLUSTER_NAME -n gpupool --node-count 1
```

## Teardown

```bash
./teardown/shutdown_sequence.sh
```

This removes the Helm release only. Secrets and PVCs are left intact
(they may be shared with other workloads, and PVCs retain model cache
for faster re-deploy). The script prints manual cleanup commands if
you want a full removal.

To delete the entire resource group:
```bash
az group delete -n $RESOURCE_GROUP --yes
```

## Production scaling

- **Dedicated GPUs:** Remove `nvidia.com/gpu: 0` and `NVIDIA_VISIBLE_DEVICES` overrides, assign GPUs per service (default chart uses 8 GPUs).
- **Multiple replicas:** Scale `vss.replicas` for parallel video processing, add GPU nodes with `az aks nodepool scale`.
- **Guardrails:** Remove `DISABLE_GUARDRAILS: "true"` and use a larger LLM (e.g., `llama-3.1-70b-instruct`).
- **Audio transcription:** Enable Riva ASR — see [official docs](https://docs.nvidia.com/vss/latest/content/vss_dep_helm.html#vss-enable-audio).

See [VSS Helm Deployment](https://docs.nvidia.com/vss/latest/content/vss_dep_helm.html) for full configuration options.

## Notes

- All services share GPU 0 via `NVIDIA_VISIBLE_DEVICES=0` with `nvidia.com/gpu: 0` (bypasses device plugin).
- The overrides file includes `fsGroup: 1000` for nemo-rerank to fix PVC permission issues.
- GPU Operator on AKS: fresh clusters on K8s 1.33+ require `toolkit.enabled=true`.
- Names in `overrides-single-gpu.yaml` must match your cluster setup (`agentpool: gpupool`, `ngc-docker-reg-secret`).
- Internal service passwords in `secrets.sh` match the Helm chart defaults — override for production.
- All resources are deployed into the current kubectl namespace context (default: `default`). Use a dedicated cluster or namespace to avoid conflicts with other workloads.
- Tested on AKS with Kubernetes 1.33. If the default AKS version changes, you can pin it with `--kubernetes-version 1.33` in the `az aks create` command.
