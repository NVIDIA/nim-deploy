# Using the NVIDIA NIM for LLMs helm chart

The NIM Helm chart requires a Kubernetes cluster with appropriate GPU nodes and the [GPU Operator](https://github.com/NVIDIA/gpu-operator) installed.

The files in this repo are for reference, for the official NVIDIA AI Enterprise supported release, see [NGC](https://catalog.ngc.nvidia.com/orgs/nim/helm-charts/nim-llm) and the [official documentation](https://docs.nvidia.com/nim/large-language-models/latest/deploy-helm.html).


## Setting up the environment

Set the **NGC_API_KEY** environment variable to your NGC API key, as shown in the following example.

```bash
export NGC_API_KEY="key from ngc"
```

If you have not set up NGC, see the [NGC Setup](https://ngc.nvidia.com/setup) topic.

Clone this repository and change directories into `nim-deploy/helm`. The following commands must be run from that directory.

```
git clone git@github.com:NVIDIA/nim-deploy.git
cd nim-deploy/helm
```

## Select a NIM to use in your helm release

Each NIM contains an AI model, application, or workflow. All files necessary to run the NIM are encapsulated in the container that is available on [NGC](https://ngc.nvidia.com/). The [NVIDIA API Catalog](https://build.nvidia.com) provides a sandbox to experiment with NIM APIs prior to container and model download.

## Setting up your helm values

All available helm values can be discoved by running the `helm` command after downloading the repo.

```bash
helm show values nim-llm/
```

See the chart's [readme](nim-llm/README.md) for information about the options, including their default values. Pay particular attention to the image.repository and image.tag options if you do not want to deploy the default image for this chart.

You don't need a values file to run llama3-8b-instruct using the NIM 1.0.0 release. For an example, see [Launching a default NIM with minimal values](#Launching-a-NIM-with-a-minimal-configuration).

## Create a namespace

For the rest of this guide, we will use the namespace `nim`.

```bash
kubectl create namespace nim
```

## Launching a NIM with a minimal configuration

You can launch `llama3-8b-instruct` using a default configuration while only setting the NGC API key and persistence in one line with no extra files. Set `persistence.enabled` to **true** to ensure that permissions are set correctly and the container runtime filesystem isn't filled by downloading models.

```bash
helm --namespace nim install my-nim nim-llm/ --set model.ngcAPIKey=$NGC_API_KEY --set persistence.enabled=true
```

## Using a custom values file

When deploying NIMs there are several values that can be customized to control factors such as scaling, metrics collection, resource use, and most general AI model selection.

The following example uses meta/llama-3-8b-instruct with an existing secret as the value of the NGC API key, sets the persistent value stores to maintain the model cache and a specific non-default image pull secret, and disables the StatefulSet setup so that it deploys a Deployment object instead.

If you specify secrets as shown in this example, you cannot set the API key directly in the file or on the CLI. Instead, first create the secrets, as shown in the following example:

```bash
kubectl -n nim create secret docker-registry registry-secret --docker-server=nvcr.io --docker-username='$oauthtoken' --docker-password=$NGC_API_KEY

kubectl -n nim create secret generic ngc-api --from-literal=NGC_API_KEY=$NGC_API_KEY
```

NOTE: If you created these secrets in the past, the key inside the ngc-api secret has changed to NGC_API_KEY to be consistent with the variables used by NIMs. Please update your secret accordingly.

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

### Launching NIM in Kubernetes with a values file

Then use a command like the following, which uses the latest chart version to install the version of NIM that is defined in the values file into the `nim` namespace in your Kubernetes cluster.

```bash
helm --namespace nim install my-nim nim-llm/ -f ./custom-values.yaml
```

## A Note on Storage

The image and the model files are fairly large (> 10GB, typically), so ensure that however you are managing the storage for your helm release, you
have enough space to host both the image. If you have a persistent volume setup available to you, as you do in most cloud
providers, it is recommended that you use it. If you need to be able to deploy pods quickly and would like to be able to skip the model download step, there is an advantage to using a shared volume such as NFS as your storage setup. To try this out, it is simplest to use a normal persistent volume claim. See the Kubernetes [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) documentation for more information.

Another strategy for scaling is to deploy the chart with StatefulSet enabled (default) and persistence enabled, scale the resulting StatefulSet to the maximum number of replicas you would like to use and then, after the pods become ready, scale down again. This will retain the PVCs to be used when you scale the set up again.

## Running inference

If you are operating on a fresh persistent volume or similar, you may have to wait a little while for the model to download. You can check the status of your deployment by running

```bash
kubectl get pods -n nim
```
And check that the pods have become "Ready".

Once that is true, you can try something like:

```bash
helm -n nim test my-nim --logs
```

Which will run some simple inference requests. If the three tests pass, you'll know the deployment was successful.

Avoid setting up external ingress without adding an authentication layer. This is because NIM doesn't provide authentication on its own. The chart provides options for basic ingress.

Since this example assumes you aren't using an ingress controller, simply port-forward the service so that you can try it out directly.

```bash
kubectl -n nim port-forward service/my-nim-nim-llm 8000:8000
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
