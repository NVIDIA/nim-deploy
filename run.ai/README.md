# NIMs on Run.ai

Run.ai provides a fast and efficient platform for running AI workloads. It sits on top of a group of Kubernetes clusters and provides UI, GPU-aware scheduling, container orchestration, node pooling, organizational resource quota management, and more. It gives customers the tools to manage resources across multiple Kubernetes clusters and subdivide them across project and departments, and automates Kubernetes primitives with its own AI optimized resources.

## InferenceWorkload

Run.ai provides an [InferenceWorkload](https://docs.run.ai/latest/Researcher/workloads/inference-overview/) resource to help automate inference services like NIMs. It leverages Knative to automate the underlying service and routing of traffic.

It should be noted that InferenceWorkload is an optional add-on for Run.ai. Consult your Run.ai UI portal or cluster administrator to determine which clusters support InferenceWorkload.

### Basic Example

At the core, running NIMs with InferenceWorkload is quite simple. However, many customizations are possible, such as adding variables, PVCs to cache models, health checks, and other special configurations that will pass through to the pods backing the services. The `examples` directory can evolve over time with more complex deployment examples. The following example is a bare minimum configuration.

This example can also be deployed through [UI](https://docs.run.ai/latest/Researcher/workloads/inference-overview/) - including creating the secret and InferenceWorkload.

**Prerequisites**:
* A Runai Project (and corresponding Kubernetes namespace, which is the project name prefixed with `runai-`). You should be set up to run "kubectl" commands to the target cluster and namespace.
* An NGC API Key
* `curl` and `jq` for the test script
* A Docker registry secret for `nvcr.io` needs to exist in your Run.ai project. This can only be created through the UI, via "credentials" section. Add a new docker-registry credential, choose the scope to be your project, set username to `$oauthtoken` and password to your NGC API key. Set the registry url to `ngcr.io`. This only has to be done once per scope, and Run.ai will detect and use it when it is needed.

1. Deploy InferenceWorkload to your current Kubernetes context via Helm, with working directory being the same as this README, setting the neccessary environment variables

```
% export NAMESPACE=[namespace]
% export NGC_KEY=[ngc key]
% helm install --set namespace=$NAMESPACE --set ngcKey=$NGC_KEY my-llama-1 examples/basic-llama
```

Now, wait for the InferenceWorkload's ksvc to become ready.

```
% kubectl get ksvc basic-llama -o wide --watch
NAME          URL                                                                                                     LATESTCREATED       LATESTREADY   READY     REASON
basic-llama   http://basic-llama.runai-myproject.inference.12345678.dgxc.ngc.nvidia.com   basic-llama-00001                 Unknown   RevisionMissing
basic-llama   http://basic-llama.runai-myproject.inference.12345678.dgxc.ngc.nvidia.com   basic-llama-00001   basic-llama-00001   Unknown   RevisionMissing
basic-llama   http://basic-llama.runai-myproject.inference.12345678.dgxc.ngc.nvidia.com   basic-llama-00001   basic-llama-00001   Unknown   IngressNotConfigured
basic-llama   http://basic-llama.runai-myproject.inference.12345678.dgxc.ngc.nvidia.com   basic-llama-00001   basic-llama-00001   Unknown   Uninitialized
basic-llama   http://basic-llama.runai-myproject.inference.12345678.dgxc.ngc.nvidia.com   basic-llama-00001   basic-llama-00001   True
```

2. Query your new inference service

As seen above, you will get a new knative service accessible via hostname-based routing. Use the hostname from this URL to pass to the test script by setting an environment variable `LHOST`.

```
% export LHOST="basic-llama.runai-myproject.inference.12345678.dgxc.ngc.nvidia.com"
% ./examples/query-llama.sh
Here's a song about pizza:

**Verse 1**
I'm walkin' down the street, smellin' something sweet
Followin' the aroma to my favorite treat
A slice of heaven in a box, or so I've been told
Gimme that pizza love, and my heart will be gold
```

3. Remove inference service

```
% helm uninstall my-llama-1
release "my-llama-1" uninstalled
```
### PVC Example

The PVC example runs in much the same way. It adds a mounted PVC to the example NIM container in a place where it can be used as a cache - `/opt/nim/.cache`, and configured to be retained between helm uninstall and install, so that the model data need only be downloaded on first use.

```
% helm install --set namespace=$NAMESPACE --set ngcKey=$NGC_KEY my-llama-pvc examples/basic-llama-pvc

% kubectl get ksvc basic-llama-pvc --watch
```

### Troubleshooting

Users can troubleshoot workloads by looking at the underlying resources that are created. There should be deployments, pods, ksvcs to describe or view logs from.
