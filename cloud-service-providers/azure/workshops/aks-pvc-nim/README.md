# Llama 3.1-8b  NIM Deployment Guide with AKS PVC Installation 

## Overview
This notebook demonstrates how to deploy the Llama 3.1 8B Instruct NIM (NVIDIA Inference Microservice) on Azure Kubernetes Service (AKS) with persistent storage using Azure Files for model weights caching.

## Prerequisites
- Access to at least 1 GPU (Example uses standard_nc24ads_a100_v4 - A100 80GB GPU)
- Access to a GPU-enabled Kubernetes cluster
- `kubectl` and `helm` CLI tools installed
- Access to GPU node pools
- NGC API key for accessing NVIDIA containers and models


## Get-started Demo Notebook:
Please follow [demo notebook](aks-pvc-nim-deploy.ipynb) to get started 


## Demo Notebook Overview:

### 1. Initial Infrastructure Setup
- Creates Azure resource group and AKS cluster
- Configures basic node pool with Standard_D4s_v3 VM size
- Sets up cluster credentials and context

### 2. Storage Configuration
- Creates Azure Storage Account and File Share
- Sets up 600GB persistent volume for Hugging Face models
- Configures storage access and network rules
- Creates Kubernetes secrets for storage credentials

### 3. Persistent Volume Setup
- Creates PersistentVolume (PV) and PersistentVolumeClaim (PVC)
- Configures ReadWriteMany access mode
- Implements storage class: azurefile
- Deploys debug pod to verify storage functionality

### 4. GPU Infrastructure
- Adds GPU node pool with A100 GPU (standard_nc24ads_a100_v4)
- Installs NVIDIA GPU Operator via Helm
- Configures GPU drivers and container runtime

### 5. NIM Deployment Steps
- **Helm Chart Setup**
   - Fetches NIM LLM Helm chart from NGC
   - Creates necessary NGC secrets for pulling images
   - Sets up registry secrets for nvcr.io access

- **NIM Configuration**
   - Creates custom values file for Helm deployment
   - Configures model repository and version
   - Sets up volume mounts for model caching
   - Configures GPU resource limits

- **Model Deployment**
   - Installs Llama 3.1 8B Instruct model using Helm
   - Mounts PVC for model weight persistence
   - Configures environment variables for caching

### 6. Testing and Verification
- **Service Access**
   - Sets up port forwarding to access the NIM service
   - Exposes service on port 8000

- **Model Testing**
   - Tests model using chat completions API
   - Verifies model responses using curl commands
   - Checks model availability through API endpoints




## Cleanup
Includes commands for:
- Stopping AKS cluster
- Deleting resource group
- Cleaning up Kubernetes resources
