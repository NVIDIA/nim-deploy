# NVIDIA NIM Operator on Azure AKS:

Please see the NIM Operator documentation before you proceed: https://docs.nvidia.com/nim-operator/latest/index.html
The files in this repo are for reference, for the official NVIDIA AI Enterprise supported release, see NGC and the official documentation.
Helm and GPU Operator should be installed in the cluster before proceeding with the steps below. 
[Pre-requisites](https://docs.nvidia.com/nim-operator/latest/install.html#prerequisites)

Follow the instructions for the NIM Operator installation: https://docs.nvidia.com/nim-operator/latest/install.html#install-nim-operator


# Caching Models

Follow the instructions in the [docs](https://docs.nvidia.com/nim-operator/latest/cache.html#procedure) using the sample manifest file below.
   
The image and the model files are fairly large (> 10GB, typically), so ensure that however you are managing the storage for your helm release, you have enough space to host both the image. If you have a persistent volume setup available to you, as you do in most cloud providers, it is recommended that you use it. If you need to be able to deploy pods quickly and would like to be able to skip the model download step, there is an advantage to using a shared volume such as NFS as your storage setup.  

Follow instructions to create a custom storage class that uses NFS protocol:  https://learn.microsoft.com/en-us/troubleshoot/azure/azure-kubernetes/storage/fail-to-mount-azure-file-share#solution-2-create-a-pod-that-can-be-scheduled-on-a-fips-enabled-node

Create a nimcache using the sample file that leverages the custom storage class you created (e.g. azurefile-sc-fips):

```yaml
apiVersion: apps.nvidia.com/v1alpha1
kind: NIMCache
metadata:
  name: meta-llama3-8b-instruct
spec:
  source:
    ngc:
      modelPuller: nvcr.io/nim/meta/llama3-8b-instruct:1.0.3
      pullSecret: ngc-secret
      authSecret: ngc-api-secret
      model:
        engine: tensorrt_llm
        tensorParallelism: "1"
  storage:
    pvc:
      create: true
      storageClass: azurefile-sc-fips
      size: "50Gi"
      volumeAccessMode: ReadWriteMany
  resources: {}
```
 
# Creating a NIM Service 

1. Follow the instructions in the [docs](https://docs.nvidia.com/nim-operator/latest/service.html#procedure) using the sample yaml file below.

```yaml
apiVersion: apps.nvidia.com/v1alpha1
kind: NIMService
metadata:
  name: meta-llama3-8b-instruct
spec:
  image:
    repository: nvcr.io/nim/meta/llama3-8b-instruct
    tag: 1.0.3
    pullPolicy: IfNotPresent
    pullSecrets:
      - ngc-secret
  authSecret: ngc-api-secret
  storage:
    nimCache:
      name: meta-llama3-8b-instruct
      profile: ''
  replicas: 1
  resources:
    limits:
      nvidia.com/gpu: 1
  expose:
    service:
      type: ClusterIP
      port: 8000
```    

# Sample request and response:

Avoid setting up external ingress without adding an authentication layer. This is because NIM doesn't provide authentication on its own. The chart provides options for basic ingress.

Since this example assumes you aren't using an ingress controller, simply port-forward the service so that you can try it out directly.

```bash
kubectl -n nim-service port-forward service/meta-llama3-8b-instruct 8000:8000
```

Then try a request:

```bash
curl -X 'POST' \
  'http://localhost:8000/v1/chat/completions' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
  "messages": [
    {
      "content": "You are a polite and respectful chatbot helping people plan a vacation.",
      "role": "system"
    },
    {
      "content": "What should I do for a 4 day vacation in Spain?",
      "role": "user"
    }
  ],
  "model": "meta/llama3-8b-instruct",
  "max_tokens": 16,
  "top_p": 1,
  "n": 1,
  "stream": false,
  "stop": "\n",
  "frequency_penalty": 0.0
}'
```
