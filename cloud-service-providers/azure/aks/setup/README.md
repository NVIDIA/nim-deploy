# Setup Azure Kubernetes Service (AKS)

The key to creating Azure Kubernetes Service (AKS) for NIM is to create proper GPU nodepool.  The following steps guide you how to find it.

## Connect to Azure

```
az login --use-device-code
az account set --subscription <subscription name>
```

## Identify GPU needed for NIM

- Go to NIM document to find the GPU you [need](https://docs.nvidia.com/nim/large-language-models/latest/support-matrix.html) and convert to Azure VM

Following is the example

### Llama 3 8B Instruct

| GPU   | GPU Memory  | Precision | Profile    | # of GPUS | Azure VM Instance         | Azure VM Family |
| ----- | ----------- | --------- | ---------- | --------- | ------------------------- | --------------- |
| H100  | 94          | FP8       | Throughput | 1         | Standard_NC40adis_H100_v5 | NCads H100 v5   |
| H100  | 188         | FP8       | Latency    | 2         | Standard_NC80adis_H100_v5 | NCads H100 v5   |
| H100  | 94          | FP16      | Throughput | 1         | Standard_NC40adis_H100_v5 | NCads H100 v5   |
| H100  | 188         | FP16      | Latency    | 2         | Standard_NC80adis_H100_v5 | NCads H100 v5   |
| A100  | 80          | FP16      | Throughput | 1         | Standard_NC24ads_A100_v4​  | NCADS_A100_v4   |
| A100  | 160         | FP16      | Latency    | 2         | Standard_NC48ads_A100_v4  | NCADS_A100_v4   |
| L40S  | 48          | FP8       | Throughput | 1         |                                             |
| L40S  | 96          | FP8       | Latency    | 2         |                                             |
| L40S  | 48          | FP16      | Throughput | 1         |                                             |
| A10G  | 24          | FP16      | Throughput | 1         | Standard_NV36ads_A10_v5   | NVadsA10 v5     |
| A10G  | 48          | FP16      | Latency    | 2         | Standard_NV72ads_A10_v5   | NVadsA10 v5     |

### Llama 3 70B Instruct

| GPU   | GPU Memory  | Precision | Profile    | # of GPUS | Azure VM Instance         | Azure VM Family |
| ----- | ----------- | --------- | ---------- | --------- | ------------------------- | --------------- |
| H100  | 320         | FP8       | Throughput | 4         | Standard_ND96isr_H100_v5  | ND H100 v5      |
| H100  | 640         | FP8       | Latency    | 8         | Standard_ND96isr_H100_v5  | ND H100 v5      |
| H100  | 320         | FP16      | Throughput | 4         | Standard_ND96isr_H100_v5  | ND H100 v5      |
| H100  | 640         | FP16      | Latency    | 8         | Standard_ND96isr_H100_v5  | ND H100 v5      |
| A100  | 320         | FP16      | Throughput | 4         | Standard_ND96amsr_A100_v4​ | NDAMSv4_A100    |
| L40S  | 192         | FP8       | Throughput | 4         |
| L40S  | 384         | FP8       | Latency    | 8         |

## Find the region has desired GPU

Got to https://azure.microsoft.com/en-us/explore/ to search for VM instacne and you can find the region has that GPU.

Following are the search result up to today (June 2024)

|  VM Family    |           Regions                                                                  |
| ------------- | ---------------------------------------------------------------------------------- |
| NCADS_A100_v4 | South Central US, East US, Southeast Asia                                          |
| NDAMSv4_A100  | East United States, West United States 2, West Europe, South Central United States |
| NCads H100 v5 | West United States 3, South Central United States                                  |
| ND H100 v5    | East United States, South Central United States                                    |

## Request Quota

Please study the follow [link](https://www.youtube.com/watch?v=Y8-E-mVAEsI&t=43s)  If you failed in the later operation due to not enough quota limit.

## Create AKS

```
az aks create -g <resource group name> -n <aks name> --location <location has desired GPU> --zones <zone has desired GPU> --generate-ssh-keys
```

## Create GPU nodepool

```
az aks nodepool add --resource-group <resource group name> --cluster-name <aks name> --name <nodepool name> --node-count 1 --skip-gpu-driver-install --node-vm-size <Desire VM type> --node-osdisk-size 2048 --max-pods 110
```

## Connect to AKS

```
az aks get-credentials --resource-group <resource group name> --name <aks name>
```

## Install GPU Operator

```
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --pass-credentials
helm repo update
helm install --create-namespace --namespace gpu-operator nvidia/gpu-operator --wait --generate-name
```

Official instruction are [here](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html)
