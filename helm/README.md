# Using the NIM LLM helm chart

The NIM Helm chart requires a Kubernetes cluster with appropriate GPU nodes and the [GPU Operator](https://github.com/NVIDIA/gpu-operator) installed.


## Setting up the environment

Set the **NGC_CLI_API_KEY** environment variable to your NGC API key, as shown in the following example.

```bash
export NGC_CLI_API_KEY="key from ngc"
```

If you have not set up NGC, see the [NGC Setup](https://ngc.nvidia.com/setup) topic.

[comment]: <> (TODO: update the repo with th real location)

Clone this repository and change directories into `nim-deploy/helm`. The following commands must be run from that directory.

## Select a NIM to use in your helm release

Each NIM contains an AI model, application, or workflow. All files necessary to run the NIM are encapsulated in the container that is available on [NGC](https://ngc.nvidia.com/). The [NVIDIA API Catalog](https://build.nvidia.com) provides a sandbox to experiment with NIM APIs prior to container and model download.

## Setting up your helm values file

Available helm values can be discoved by running the `helm` command after the repo has been added.

```bash
helm show values nim-llm/
```

The chart requires certain [Kubernetes secrets](https://kubernetes.io/docs/concepts/configuration/secret/) to be configured in the cluster.

* NGC container downloads require an image pull secret (in this case named `registry-secret`).
* NGC model downloads require an NGC API key (a secret `ngc-api` that has the value stored in a key named `NGC_CLI_API_KEY`).

These secrets can be created with the following command:
```bash
kubectl create secret docker-registry registry-secret --docker-server=nvcr.io --docker-username='$oauthtoken' --docker-password=$NGC_CLI_API_KEY

kubectl create secret generic ngc-api --from-literal=NGC_CLI_API_KEY=$NGC_CLI_API_KEY
```

### Values

When deploying NIMs there are several values that can be customized to control factors such as scaling, metrics collection, resource use, and most general AI model selection.

Here is an example using meta/llama-3-8b-instruct.


```yaml
image:
  # Adjust to the actual location of the image and version you want
  repository: nvcr.io/nim/meta/llama3-8b-instruct
  tag: 1.0.0
imagePullSecrets:
  - name: registry-secret
model:
  name: meta/llama3-8b-instruct # not strictly necessary, but enables running "helm test" below
  ngcAPISecret: ngc-api
persistence:
  enabled: true
  annotations:
    helm.sh/resource-policy: keep
statefulSet:
    enabled: false
resources:
  limits:
    nvidia.com/gpu: 1
```

> **NOTE**: If Multi-instance GPUs (MIG) are enabled in the cluster, resource selection may be different. For example:

```yaml
resources:
  limits:
    nvidia.com/mig-4g.24gb: 1
```

After creating the `values.yaml` file, create a `namespace`.


```bash
kubectl create namespace inference-ms
```

## Launching NIM in Kubernetes

A command like the one below will then use the latest chart version to install the version of NIM defined in the values file into the `inference-ms` namespace in your Kubernetes cluster. Modify it as required.

```bash
helm --namespace inference-ms install my-nim nim-llm/ -f path/to/your/custom-values.yaml
```

### A Note on Storage

The image and the model files are fairly large (> 10GB, typically), so ensure that however you are managing the storage for your helm release, you
have enough space to host both the image. If you have a persistent volume setup available to you, as you do in most cloud
providers, we recommend you use it. If you need to be able to deploy pods quickly and would like to be able to skip the model download step, there is an advantage to using a shared volume such as NFS as your storage setup. To try this out, it is simplest to use a normal persistent volume claim. See the Kubernetes [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) documentation for more information.

## Running inference

If you are operating on a fresh persistent volume or similar, you may have to wait a little while for the model to download. You can check the status of your deployment by running

```bash
kubectl get pods -n inference-ms
```
And check that the pods have become "Ready".

Once that is true, you can try something like:

```bash
helm -n inference-ms helm test my-nim
```

Which will run some simple inference requests. If the three tests pass, you'll know the deployment was successful.

Since this example assumes you aren't using an ingress controller, simply port-forward the service so that you can try it out directly.

```bash
kubectl -n inference-ms port-forward service/my-nim-nim-llm 8000:8000
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
