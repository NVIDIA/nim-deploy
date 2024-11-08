## Introduction
This repo showcases different ways NVIDIA NIMs can be deployed. This repo contains reference implementations, example documents, and architecture guides that can be used as a starting point to deploy multiple NIMs and other NVIDIA microservices into Kubernetes and other production deployment environments.

> **Note**
> The content in this repository is designed to provide reference architectures and best-practices for production-grade deployments and product integrations; however the code is not validated on all platforms and does not come with any level of enterprise support. While the deployments should perform well, please treat this codebase as experimental and a collaborative sandbox. For long-term production deployments that require enterprise support from NVIDIA, looks to the official releases on [NVIDIA NGC](https://ngc.nvidia.com/) which are based on the code in this repo.

# Deployment Options

| Category                           | Deployment Option                                           | Description |
|------------------------------------|-------------------------------------------------------------|-------------|
| **On-premise Deployments**         | **Helm**                                                    |             |
|                                    | | [LLM NIM](https://github.com/NVIDIA/nim-deploy/tree/main/helm/nim-llm)                                            |             |
|                                    | | LLM NIM on OpenShift Container Platform (coming soon) |             |
|                                    | **Open Source Platforms**                                   |             |
|                                    | | [KServe](https://github.com/NVIDIA/nim-deploy/tree/main/kserve)                                             |             |
|                                    | **Independent Software Vendors**                            |             |
|                                    | | Run.ai (coming soon)                               |             |
| **Cloud Service Provider Deployments** | **Azure**                                                |             |
|                                    | | [AKS Managed Kubernetes](https://github.com/NVIDIA/nim-deploy/tree/main/cloud-service-providers/azure/aks)                             |             |
|                                    | | [Azure ML](https://github.com/NVIDIA/nim-deploy/tree/main/cloud-service-providers/azure/azureml)                                    |             |
|                                    | | [Azure prompt flow](https://github.com/NVIDIA/nim-deploy/tree/main/cloud-service-providers/azure/promptflow)                                  |             |
|                                    | **Amazon Web Services**                                     |             |
|                                    | | [EKS Managed Kubernetes](https://github.com/NVIDIA/nim-deploy/tree/main/cloud-service-providers/aws/eks)                             |             |
|                                    | | [Amazon SageMaker](https://github.com/NVIDIA/nim-deploy/tree/main/cloud-service-providers/aws/sagemaker)                                   |             |
|                                    | | [EKS Managed Kubernetes - NIM Operator](https://github.com/NVIDIA/nim-deploy/tree/main/cloud-service-providers/aws/eks/nim-operator-setup.md)                             |             |
|                                    | **Google Cloud Platform**                                   |             |
|                                    | | [GKE Managed Kubernetes](https://github.com/NVIDIA/nim-deploy/tree/main/cloud-service-providers/google-cloud/gke)                             |             |
|                                    | | [Google Cloud Vertex AI](https://github.com/NVIDIA/nim-deploy/tree/main/cloud-service-providers/google-cloud/vertexai/python)               |             |
|                                    | | [Cloud Run](https://github.com/NVIDIA/nim-deploy/tree/main/cloud-service-providers/google-cloud/cloudrun)                             |             |
|                                    | **NVIDIA DGX Cloud**                                        |             |
|                                    | | [NVIDIA Cloud Functions](https://github.com/NVIDIA/nim-deploy/tree/main/cloud-service-providers/nvidia/nvcf)                             |             |
| **Documents**         | **Deployment Guide**                                                    |             |
|                                    | | [Hugging Face NIM Deployment](https://github.com/NVIDIA/nim-deploy/tree/main/docs/hugging-face-nim-deployment)                                            |             |


## Contributions
Contributions are welcome. Developers can contribute by opening a [pull request](https://help.github.com/en/articles/about-pull-requests) and agreeing to the terms in [CONTRIBUTING.MD](CONTRIBUTING.MD).


## Support and Getting Help

Please open an issue on the GitHub project for any questions. All feedback is appreciated, issues, requested features, and new deployment scenarios included.
