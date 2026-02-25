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
- [Hugging Face Token](https://huggingface.co/settings/tokens) — accept [Cosmos-Reason2-8B](https://huggingface.co/nvidia/Cosmos-Reason2-8B) terms

## Setup

### 1. Create AKS cluster

```bash
az account set --subscription "<your-subscription>"
az group create --name rg-vss-aks --location eastus2

az aks create \
  --resource-group rg-vss-aks --name aks-vss --location eastus2 \
  --node-count 1 --node-vm-size Standard_D8s_v5 \
  --generate-ssh-keys --network-plugin azure --enable-managed-identity

az aks nodepool add \
  --resource-group rg-vss-aks --cluster-name aks-vss \
  --name gpupool --node-count 1 \
  --node-vm-size Standard_NC40ads_H100_v5 \
  --labels hardware=gpu --node-osdisk-size 512

az aks get-credentials --resource-group rg-vss-aks --name aks-vss --overwrite-existing
```

> **Do not** add taints to the GPU node pool. Pods with `nvidia.com/gpu: 0`
> (GPU sharing) won't auto-tolerate them.

### 2. Set environment variables

```bash
export NGC_API_KEY="<your-key>"
export HF_TOKEN="<your-token>"
```

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
kubectl port-forward svc/vss-service 9100:9100 &
```

| Service | URL |
|---------|-----|
| **API** | http://localhost:8100 |
| **UI** | http://localhost:9100 |

## Usage

### Summarize a video (local download)

```bash
./summarize_url.sh "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4"
```

Downloads the video locally, uploads through port-forward. Results saved to `summaries/`.

### Summarize a video (on-cluster, faster for large files)

```bash
./summarize_url_cluster.sh "https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
```

Downloads and uploads entirely inside the cluster via `kubectl exec`.
Only the small JSON request/response goes through port-forward.

### Customizing prompts

The `/summarize` API accepts three prompts (see `summarize_url.sh`):

- `prompt` — per-chunk VLM caption
- `caption_summarization_prompt` — how chunk captions are structured
- `summary_aggregation_prompt` — how the final summary is aggregated

## Cost control

```bash
# Stop GPU billing (keep cluster)
az aks nodepool scale -g rg-vss-aks --cluster-name aks-vss -n gpupool --node-count 0

# Scale back up (~5-10 min, PVCs persist so model cache is retained)
az aks nodepool scale -g rg-vss-aks --cluster-name aks-vss -n gpupool --node-count 1
```

## Teardown

```bash
./teardown/shutdown_sequence.sh

# Or delete everything
az group delete -n rg-vss-aks --yes
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
