# NIVIDA NIM Deploy on KServe
[KServe](https://github.com/kserve/kserve) provides a serverless environment on Kubernetes that is purpose-built for AI inference. This repo describes what is necessary to deploy NVIDIA NIMs onto a running KServe installation.

# Setup

The following steps assumes a running K8s cluster with KServe installed, kubectl access, and NIM access on NGC. The cluster will need a StorageClass that can provide a PV large enough to download and unpack the models (200GB+ for larger models), a LoadBalancer configured in the platform, and supported GPUs for the class of NIM being deployed.

A single instance of KServe can support many NIMs running the same or different models. The first few installation steps are only required once, after initial setup a new NIM can be deployed by creating a single `InferenceService` using the YAML files in (nim-models)[nim-models].

1. Ensure access to the NIM models and the NIM containers by logging into [NGC](ngc.nvidia.com) and browsing to the desired NIM artifacts.

2. Perform the NVIDIA NIM KServe setup by exporting user tokens and running the setup script. Optionally set secret values in the secrets.env file to avoid entering them on the command line.
```
export NGC_API_KEY=
export HF_TOKEN=
export NODE_NAME=


bash scripts/setup.sh
```

> *Note: It may be necessary to run with `root` privileges if the default `/raid/nim` is not accessible.

3. Modify the cluster's prometheus configuration to scrape `/metrics` on port `80` and port `9091` for all inference pods # TODO: provide example configuration

6. Create a NIM by instationating the InferenceService corresponding to the NIM model you want to run. Note that the NIMs are a triple of (model, version, gpu type+quantity), be sure to select the right yaml file. 

 > *Note: The NIM YAML files  provides are just an example, a user could create more configurations than listed by specifying different GPU quantities or architectures referencing the same NIM containers and `pvc` configurations.

7. Validate that the NIM is running by posting a query against the KServe endpoint. Additional KServe metrics are available internally on the `ClusterIP` at port `9091` on `/metrics/`

```
# KServe URL can be obtained from `kubectl get inferenceservice` or the cluster-ip from the private predictor on `kubectl get svc` depending on KServe setup.
curl http://${KSERVE_URL}/v1/models

curl http://${KSERVE_URL}/v1/chat/completions  \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta-llama3-8b-instruct",
    "messages": [{"role":"user","content":"What is KServe?"}],
    "temperature": 0.5,   
    "top_p": 1,
    "max_tokens": 1024,
    "stream": false 
    }'

curl http://${KSERVE_URL}/metrics

```

For additional example queries see the model card on [build.nvidia.com](https://build.nvidia.com/meta/llama3-70b)
