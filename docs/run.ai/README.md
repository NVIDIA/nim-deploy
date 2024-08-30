# NIMs on Run.ai

[Run.ai](https://www.run.ai/) provides a platform for accelerating AI development delivering life cycle support spanning from concept to deployment of AI workloads. It layers on top of Kubernetes starting with a single cluster but extending to centralized multi-cluster management. It provides UI, GPU-aware scheduling, container orchestration, node pooling, organizational resource quota management, and more. And it offers administrators, researchers, and developers tools to manage resources across multiple Kubernetes clusters and subdivide them across project and departments, and automates Kubernetes primitives with its own AI optimized resources.

## Run.ai Deployment Options

The Run:ai Control Plane is available as a [hosted service](https://docs.run.ai/latest/home/components/#runai-control-plane-on-the-cloud) or alternatively as a [self-hosted](https://docs.run.ai/latest/home/components/#self-hosted-control-plane) option (including in disconnected "air-gapped" environments). In either case, the control plane can manage Run:ai "cluster engine" equipped clusters whether local or remotely cloud hosted.

## Prerequisites

1. A conformant Kubernetes cluster ([RunAI K8s version requirements](https://docs.run.ai/latest/admin/overview-administrator/))
2. RunAI Control Plane and cluster(s) [installed](https://docs.run.ai/latest/admin/runai-setup/cluster-setup/cluster-install/) and operational
3. [NVIDIA GPU Operator](https://github.com/NVIDIA/gpu-operator) installed
4. General NIM requirements: [NIM Prerequisites](https://docs.nvidia.com/nim/large-language-models/latest/getting-started.html#prerequisites)
5. An NVIDIA AI Enterprise (NVAIE) License: [Sign up for NVAIE license](https://build.nvidia.com/meta/llama-3-8b-instruct?snippet_tab=Docker&signin=true&integrate_nim=true&self_hosted_api=true) or [Request a Free 90-Day NVAIE License](https://enterpriseproductregistration.nvidia.com/?LicType=EVAL&ProductFamily=NVAIEnterprise) through the NVIDIA Developer Program.
6. An NVIDIA NGC API Key: please follow the guidance in the [NVIDIA NIM Getting Started](https://docs.nvidia.com/nim/large-language-models/latest/getting-started.html#option-2-from-ngc) documentation to generate a properly scoped API key if you haven't already.

## InferenceWorkload

Run.ai provides an [InferenceWorkload](https://docs.run.ai/latest/Researcher/workloads/inference-overview/) resource to help automate inference services like NIMs. It leverages [Knative](https://github.com/knative) to automate the underlying service and routing of traffic. YAML examples can be found [here](https://docs.run.ai/latest/developer/cluster-api/submit-yaml/#inference-workload-example).

It should be noted that InferenceWorkload is an optional add-on for Run.ai. Consult your Run.ai UI portal or cluster administrator to determine which clusters support InferenceWorkload.

### Basic Example

At the core, running NIMs with InferenceWorkload is quite simple. However, many customizations are possible, such as adding variables, PVCs to cache models, health checks, and other special configurations that will pass through to the pods backing the services. The `examples` directory can evolve over time with more complex deployment examples. The following example is a bare minimum configuration.

This example can also be deployed through [UI](https://docs.run.ai/latest/Researcher/workloads/inference-overview/) - including creating the secret and InferenceWorkload.

**Preparation**:
* A Runai Project (and corresponding Kubernetes namespace, which is the project name prefixed with `runai-`). You should be set up to run "kubectl" commands to the target cluster and namespace.
* An NGC API Key
* `curl` and `jq` for the test script
* A Docker registry secret for `nvcr.io` needs to exist in your Run.ai project. This can only be created through the UI, via "credentials" section. Add a new docker-registry credential, choose the scope to be your project, set username to `$oauthtoken` and password to your NGC API key. Set the registry url to `nvcr.io`. This only has to be done once per scope, and Run.ai will detect and use it when it is needed.

1. Deploy InferenceWorkload to your current Kubernetes context via Helm, with working directory being the same as this README, setting the necessary environment variables

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
