# NVIDIA NIM on AWS Sagemaker

## Overview

NVIDIA NIM, a component of NVIDIA AI Enterprise, enhances your applications with the power of state-of-the-art large language models (LLMs), providing unmatched natural language processing and understanding capabilities. Whether you're developing chatbots, content analyzers, or any application that needs to understand and generate human language, NVIDIA NIM has you covered.

## Deployment Options

There are various ways to deploy NVIDIA NIMs on AWS SageMaker:

### 1. AWS Marketplace Deployment

This option is for users who want to deploy NIMs procured directly from the AWS Marketplace.

- [Launch NIMs from AWS Marketplace on SageMaker](aws_marketplace_notebooks)
    - [Llama 3.1 8B NIM Notebook](aws_marketplace_notebooks/nim_llama3.1-8b_aws_marketplace.ipynb)
    - [Llama 3.1 70B NIM Notebook](aws_marketplace_notebooks/nim_llama3.1-70b_aws_marketplace.ipynb)
    - [Llama 3.1 Nemotron Nano 8B v1 NIM Notebook](aws_marketplace_notebooks/nim_llama3.1-nemotron-nano-8b-v1_aws_marketplace.ipynb)
    - [Llama 3.1 Nemotron Ultra 253B NIM Notebook](aws_marketplace_notebooks/nim_llama3.1-nemotron-ultra-253b-v1_aws_marketplace.ipynb)
    - [Llama 3.2 NV EmbedQA NIM Notebook](aws_marketplace_notebooks/nim_llama3.2-nv-embedqa-1b-v2_aws_marketplace.ipynb)
    - [Llama 3.2 NV RerankQA NIM Notebook](aws_marketplace_notebooks/nim_llama3.2-nv-rerankqa-1b-v2_aws_marketplace.ipynb)
    - [Llama 3.3 Nemotron Super 49B v1 NIM Notebook](aws_marketplace_notebooks/nim_llama3.3-nemotron-super-49b-v1_aws_marketplace.ipynb)
    - [Llama 3.3 Nemotron Super 49B v1.5 NIM Notebook](aws_marketplace_notebooks/nim_llama3.3-nemotron-super-49b-v1-5_aws_marketplace.ipynb)
    - [Mixtral 8x7B NIM Notebook](aws_marketplace_notebooks/nim_mixtral_aws_marketplace.ipynb)
    - [Nemotron4-15B Notebook](aws_marketplace_notebooks/nim_nemotron15B_aws_marketplace.ipynb)
    - [NVIDIA Nemotron Nano 9B v2 NIM Notebook](aws_marketplace_notebooks/nim_nvidia-nemotron-nano-9b-v2_aws_marketplace.ipynb)

### 2. Direct Deployment from NVIDIA GPU Cloud (NGC)

This option is for users who have purchased an NVIDIA AI Enterprise license and have an NGC API key. It allows you to download NIMs artifacts directly from NVIDIA NGC and deploy them on SageMaker.

- [Deploy NIMs from NGC on SageMaker](deployment_notebooks)
    - [Llama 3 70B and 8B Instruct Notebook](deployment_notebooks/nim_llama3.ipynb)
    - [Llama 3.1 Nemotron Nano 4B v1.1 NIM Notebook](deployment_notebooks/nim_llama3.1-nemotron-nano-4b-v1.1.ipynb)
    - [Llama 3.1 Nemotron Nano 8B v1 NIM Notebook](deployment_notebooks/nim_llama3.1-nemotron-nano-8b-v1.ipynb)
    - [Llama 3.2 NV EmbedQA NIM Notebook](deployment_notebooks/nim_llama3.2-nv-embedqa-1b-v2.ipynb)
    - [Llama 3.2 NV RerankQA NIM Notebook](deployment_notebooks/nim_llama3.2-nv-rerankqa-1b-v2.ipynb)
    - [Llama 3.3 Nemotron Super 49B v1 NIM Notebook](deployment_notebooks/nim_llama3.3-nemotron-super-49b-v1.ipynb)
    - [Llama 3.3 Nemotron Super 49B v1.5 NIM Notebook](deployment_notebooks/nim_llama3.3-nemotron-super-49b-v1.5.ipynb)
    - [NVIDIA Nemotron Nano 9B v2 NIM Notebook](deployment_notebooks/nim_nvidia-nemotron-nano-9b-v2.ipynb)

### 3. Direct Deployment from Amazon S3

This option is for users who want a faster deployment by pre-uploading the NIMs model files to an S3 bucket and configuring SageMaker to preload the NIM files into the inference environment to the NIM cache location. With this option, the NIM does not download any files from NGC durign deployment 

- [Deploy NIMs from S3 on SageMaker](s3_nim_sagemaker)
    - [Llama 3.2 NV EmbedQA NIM Steps and Notebook](s3_nim_sagemaker/README.md)
## Deployment Methods

> **Note:** To deploy a NIM on AWS SageMaker, the NIM container image must be adapted to meet SageMaker's container interface requirements. Both the AWS Marketplace deployment and direct NGC deployment options above use pre-configured images that are already SageMaker-compatible.

The following resources provide instructions for users who want to build their own custom SageMaker-compatible NIM images:

### 1. Python CLI Method

For users who prefer a programmatic approach using Python to build and deploy custom SageMaker-compatible NIM images:

- [Build & Deploy a Custom NIM on SageMaker via Python CLI](README_python.md)

### 2. Shell Script Method

For users who prefer using AWS CLI and shell commands to build and deploy custom SageMaker-compatible NIM images:

- [Build & Deploy a Custom NIM on SageMaker via Shell](README_shell.md)

## Prerequisites

- AWS account with appropriate permissions
- For AWS Marketplace deployment: Subscription to the desired model in AWS Marketplace
- For Direct NGC deployment: NVIDIA AI Enterprise license and NGC API key
- Docker installed (for building custom images)
- AWS CLI configured (for CLI and shell deployments)
