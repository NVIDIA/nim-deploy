# NIVIDA NIM Deploy on KServe
[KServe](https://github.com/kserve/kserve) provides a serverless environment on Kubernetes that is purpose-built for AI inference. This project describes what is necessary to deploy NVIDIA NIMs onto a running KServe installation.

# Setup

The following steps assumes a running K8s cluster with KServe installed, kubectl access, and NIM access on NGC. The cluster will need a StorageClass that can provide a PV large enough to download and unpack the models (200GB+ for larger models), a LoadBalancer configured in the platform, and supported GPUs for the class of NIM being deployed.

A single instance of KServe can support many NIMs running the same or different models. The first few installation steps are only required once, after initial setup a new NIM can be deployed by creating a single `InferenceService` using the YAML files in [nim-models](https://github.com/NVIDIA/nim-deploy/tree/main/kserve/nim-models).

1. Ensure access to the NIM models and the NIM containers by logging into [NGC](https://ngc.nvidia.com/) and browsing to the desired NIM artifacts.

2. Perform the NVIDIA NIM KServe setup by exporting user tokens and running the setup script. Optionally set secret values in the secrets.env file to avoid entering them on the command line.
```
export NGC_API_KEY=
export HF_TOKEN=
export NODE_NAME=


bash scripts/setup.sh
```

> **Note**: It may be necessary to run with `root` privileges if the default `/raid/nim` is not accessible.

3. Modify the cluster's prometheus configuration to scrape `/metrics` on port `80` and port `9091` for all inference pods # TODO: provide example configuration

4. Create the NIM cache locally. KServe currently requires that PVCs are mounted to a Pod in ReadOnly mode (see this [issue](https://github.com/kserve/kserve/issues/3687)), because of this the NIM cache must be created outside of NIM `InferenceService` deployment.

> For faster testing purposes this step can be bypassed by setting the NIM to re-download the model each time by setting `NIM_CACHE_PATH` to `/tmp` in the runtime files.

The default `setup.sh` script creates a PV that points to the local hostpath at `/raid/nvidia-nim`. NIM can be run locally following the [official docs](https://docs.nvidia.com/nim/large-language-models/latest/getting-started.html#launch-nvidia-nim-for-llms) to initially populate this cache. The NIM container can be run locally with Docker or in the cluster as a Pod, Job, or Deployment. The best method for cache creation will depend on the type of distributed storage being used to back the PVC.

5. Create a NIM by instationating the InferenceService corresponding to the NIM model you want to run. See the NIM  `InferenceService` [README](https://github.com/NVIDIA/nim-deploy/blob/main/kserve/nim-models/README.md) for selecting the correct yaml spec of yaml customization. Note that the NIMs are a combination of model, version, gpu type/quantity, be sure to select the right yaml file for the available cluster hardware.

```
# Create an InferenceService for Llama3-8b running on any 1 GPU
kubectl create -f nim-models/llama3-8b-instruct_1xgpu_1.0.0.yaml

# Create an InferenceService for Llama3-8b running on 2 A100-80GB GPUs
kubectl create -f nim-models/llama3-8b-instruct_2xa100_1.0.0.yaml

# Create an InferenceService for Llama3-70b running on 4 H100-80GB GPUs
kubectl create -f nim-models/llama3-70b-instruct_4xh100_1.0.0.yaml
```

 > **Note**: The NIM YAML files  provides are just an example, a user could create more configurations than listed by specifying different GPU quantities or architectures referencing the same NIM containers and `pvc` configurations.

6. Validate that the NIM is running by posting a query against the KServe endpoint. Additional KServe metrics are available internally on the `ClusterIP` at port `9091` on `/metrics/`

```
# KServe URL can be obtained from `kubectl get inferenceservice` or the cluster-ip from the private predictor on `kubectl get svc` depending on KServe setup.

# Validate the NIM Models List API
curl http://${KSERVE_URL}/v1/models

# Validate the LLM NIM Chat Completions API
curl http://${KSERVE_URL}/v1/chat/completions  \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta/llama3-8b-instruct",
    "messages": [{"role":"user","content":"What is KServe?"}],
    "temperature": 0.5,   
    "top_p": 1,
    "max_tokens": 1024,
    "stream": false 
    }'

# Validate the Embedding NIM Embeddings API
curl -X POST  http://${KSERVE_URL}/v1/embeddings  \
  -H "Content-Type: application/json" \
  -d '{
    "input": ["What is the capital of France?"],
    "model": "nv-embedqa-e5-v5",
    "input_type": "query",
    "encoding_format": "float",
    "truncate": "NONE"
  }'

# Validate the LLM NIM Metrics API
curl http://${KSERVE_URL}/metrics

```

For additional example queries see the model card on [build.nvidia.com](https://build.nvidia.com/meta/llama3-70b)
