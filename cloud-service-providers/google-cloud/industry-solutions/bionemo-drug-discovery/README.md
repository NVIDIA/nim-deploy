# NVIDIA BioNeMo Blueprint: Generative Virtual Screening for Drug Discovery

*Disclaimer: This sample is based on this [repository](https://github.com/NVIDIA-BioNeMo-blueprints/generative-virtual-screening). For the most up to date information, please refer to it.*

## Overview

The NVIDIA BioNeMo Blueprint for generative virtual screening shows how generative AI and accelerated BioNeMo NIMs (NVIDIA Inference Microservices) can be used to design optimized small molecules smarter and faster. This Blueprint creates a streamlined virtual screening workflow for drug discovery. It highlights the use of cutting-edge generative AI models and GPU-accelerated microservices to predict protein structures, generate optimized molecules, and perform protein-ligand docking.

The workflow is applied to the SARS-CoV-2 main protease and Nirmatrelvir as an example, but it is highly flexible and can be adapted to any protein or molecule of interest. By combining these models, the notebook showcases the power of NVIDIA’s BioNeMo NIMs in accelerating drug discovery through AI-driven insights and predictions.

## Software Components
Here’s an overview of the key NVIDIA NIMs featured in this workflow:
- **MSA-Search (MMSeqs2)**: A GPU-accelerated toolkit for multiple sequence alignment, providing co-evolutionary information crucial for accurate protein structure prediction.
- **OpenFold2**: A transformer-based generative model for predicting 3D protein structures from amino acid sequences, leveraging MSA data to enhance structural accuracy.
- **GenMol**: A masked diffusion model designed for molecular generation and optimization, enabling the creation of drug-like molecules tailored to specific chemical properties.
- **DiffDock**: A state-of-the-art generative model for protein-ligand docking that predicts binding poses without requiring predefined binding pockets, facilitating blind docking.

### Hardware Requirements

The following specifications are required:
- At least 1300 GB (1.3 TB) of fast NVMe SSD space. (For MSA databases)
- A modern CPU with at least 24 CPU cores
- At least 64 GB of RAM
- 4 X NVIDIA L40s, A100, or H100 GPUs across your cluster.


### Infrastructure Provisioning

1. Declare NGC API key

```bash
export NGC_API_KEY=<add your key here>
```

2. Set other environment variables:

```bash
export PROJECT_ID=$GOOGLE_CLOUD_PROJECT 
export ZONE=us-central1-b	
export CLUSTER_NAME=bionemo-demo 
export NODE_POOL_MACHINE_TYPE=g2-standard-48
export CLUSTER_MACHINE_TYPE=e2-standard-4
export GPU_TYPE=nvidia-l4 
export GPU_COUNT=4 
export LOCAL_SSD_PARTITIONS=4
export WORKLOAD_POOL=$PROJECT_ID.svc.id.goog

export CHART_NAME=bionemo-chart
export NAMESPACE=bionemo
```

3. Create cluster

```bash
gcloud container clusters create ${CLUSTER_NAME} \
    --project=${PROJECT_ID} \
    --location=${ZONE} \
    --workload-pool=${WORKLOAD_POOL} \
    --machine-type=${CLUSTER_MACHINE_TYPE} \
    --num-nodes=1
```

4. Create node pool

This command adds a pool with attached GPUs and local SSDs for high-performance workloads.

```bash
gcloud container node-pools create gpupool \
    --accelerator="type=${GPU_TYPE},count=${GPU_COUNT},gpu-driver-version=latest" \
    --project=${PROJECT_ID} \
    --cluster=$CLUSTER_NAME \
    --ephemeral-storage-local-ssd count=$LOCAL_SSD_PARTITIONS \
    --num-nodes=1 \
    --location=$ZONE \
    --machine-type=$NODE_POOL_MACHINE_TYPE
```
### Blueprint Deployment 

1. Clone the Repository

```bash
git clone https://github.com/NVIDIA-BioNeMo-blueprints/generative-virtual-screening.git

cd generative-virtual-screening

git checkout 50c39b742c05b0aca492dca8b6ef53f98b11ff52
```

2. Move configuration file to helm chart

```bash
mv ../values.yaml generative-virtual-screening/generative-virtual-screening-chart/values.yaml 
```

3. Install helm chart

```bash
cd generative-virtual-screening/generative-virtual-screening-chart

kubectl create namespace $NAMESPACE

kubectl create secret generic ngc-registry-secret --from-literal=NGC_REGISTRY_KEY=$NGC_API_KEY -n $NAMESPACE

helm install "${CHART_NAME}" . -n $NAMESPACE
```

4. Verify PODs are running - it could take up to 3 hours to start.

```bash
kubectl get pods
```

### Accessing Services

The blueprint is composed of four services. To connect to each service, use the following `kubectl port-forward` commands in separate terminal sessions:

1. Connect to msa service:
   ```bash
   echo "Connect to msa on http://127.0.0.1:8081"
   kubectl port-forward --namespace $NAMESPACE svc/bionemo-chart-generative-virtual-screening-chart-msa 8081:8081
   ```

2. Connect to openfold2 service:
   ```bash
   echo "Connect to openfold2 on http://127.0.0.1:8082"
   kubectl port-forward --namespace $NAMESPACE svc/bionemo-chart-generative-virtual-screening-chart-openfold2 8082:8082
   ```

3. Connect to genmol service:
   ```bash
   echo "Connect to genmol on http://127.0.0.1:8083"
   kubectl port-forward --namespace $NAMESPACE svc/bionemo-chart-generative-virtual-screening-chart-genmol 8083:8083
   ```

4. Connect to diffdock service:
   ```bash
   echo "Connect to diffdock on http://127.0.0.1:8084"
   kubectl port-forward --namespace $NAMESPACE svc/bionemo-chart-generative-virtual-screening-chart-diffdock 8084:8084
   ```

### Run notebook

Navigate to Jupyter notebook location

```bash
cd ../src
```

Launch the Jupyter notebook in this directory and run it!

## Cleanup

After you have finished, run the following command to delete the GKE cluster and all associated resources to avoid incurring further costs. 🧹

```bash
gcloud container clusters delete $CLUSTER_NAME --zone=$ZONE
```