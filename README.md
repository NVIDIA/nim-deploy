## Introduction
This repo is intended to aggregate and showcase different ways NVIDIA NIMs can be deployed. It contains reference implementations, deployment guides, examples, and architecture guidance that can be used as a starting point to deploy multiple NIMs and other NVIDIA microservices into Kubernetes and other production deployment environments.  Many of the most common NIM deployment and lifecycle scenarios addressed here may be addressed by capabilities afforded by the [NVIDIA NIM Operator](https://github.com/NVIDIA/k8s-nim-operator) as it progresses.

> **Note**
> The content in this repository is designed to provide reference architectures and best-practices for production-grade deployments and product integrations; however the code is not validated on all platforms and does not come with any level of enterprise support. While the deployments should perform well, please treat this codebase as experimental and a collaborative sandbox. For long-term production deployments that require enterprise support from NVIDIA, looks to the official releases on [NVIDIA NGC](https://ngc.nvidia.com/) which are based on the code in this repo.

# Deployment Options

**Tools & Guides** 
| Category                           | Type               | Description |
|------------------------------------|-------------------------------------------------------------|-------------|
| Open Source                        | Helm Chart(s)      | [LLM NIM](https://github.com/NVIDIA/nim-deploy/tree/main/helm/nim-llm)                               |      |
| Open Source Platform               | Deployment Guide   | [KServe](https://github.com/NVIDIA/nim-deploy/tree/main/kserve)                                      |      |
| Commercial Platform                | Deployment Guide   | [Run.ai](https://github.com/NVIDIA/nim-deploy/tree/main/docs/runai)                                  |      |
| Commercial Platform                | Deployment Guide   | [Hugging Face NIM Deployment](https://github.com/NVIDIA/nim-deploy/tree/main/docs/hugging-face-nim-deployment) |      |
|                                    |                    | LLM NIM on OpenShift Container Platform (coming soon)                                                |      |

**Managed Cloud Services**

| Service                            | Type               | Description |
|------------------------------------|-------------------------------------------------------------|-------------|
|                                    | |                  |
| Microsoft Azure                    | Deployment Guide   | [AKS Managed Kubernetes](https://github.com/NVIDIA/nim-deploy/tree/main/cloud-service-providers/azure/aks)           |        |
| Microsoft Azure                    | Deployment Guide   | [Azure ML](https://github.com/NVIDIA/nim-deploy/tree/main/cloud-service-providers/azure/azureml)                     |        |
| Microsoft Azure                    | Deployment Guide   | [Azure prompt flow](https://github.com/NVIDIA/nim-deploy/tree/main/cloud-service-providers/azure/promptflow)         |        |
|                                    | |             |
| Amazon Web Services                | Deployment Guide   | [EKS Managed Kubernetes](https://github.com/NVIDIA/nim-deploy/tree/main/cloud-service-providers/aws/eks)             |        |
| Amazon Web Services                | Deployment Guide   | [Amazon SageMaker](https://github.com/NVIDIA/nim-deploy/tree/main/cloud-service-providers/aws/sagemaker)             |        |
|                                    | |             |
| Google Cloud Platform              | Deployment Guide   | [GKE Managed Kubernetes](https://github.com/NVIDIA/nim-deploy/tree/main/cloud-service-providers/google-cloud/gke)    |        |
| Google Cloud Platform              | Deployment Guide   | [Google Cloud Vertex AI](https://github.com/NVIDIA/nim-deploy/tree/main/cloud-service-providers/google-cloud/vertexai/python) |        |
| Google Cloud Platform              | Deployment Guide   | [Cloud Run](https://github.com/NVIDIA/nim-deploy/tree/main/cloud-service-providers/google-cloud/cloudrun)            |        |
|                                    | |             |
| NVIDIA DGX Cloud                   | Deployment Guide   | [NVIDIA Cloud Functions](https://github.com/NVIDIA/nim-deploy/tree/main/cloud-service-providers/nvidia/nvcf)         |        |
|                                    | |             |

## Contributions
Contributions are welcome. Developers can contribute by opening a [pull request](https://help.github.com/en/articles/about-pull-requests) and agreeing to the terms in [CONTRIBUTING.MD](CONTRIBUTING.MD).

## Support and Getting Help

Please open an issue on the GitHub project for any questions. All feedback is appreciated, issues, requested features, and new deployment scenarios included.
