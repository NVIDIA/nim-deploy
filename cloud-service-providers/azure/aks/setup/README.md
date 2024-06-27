# Setup AKS

The keys to create AKS for NIM is to create proper GPU nodepool.  Details are in the following table. 

## Connect to Azure

```
az login --use-device-code
az account set --subscription <subscription name>
```

## Create AKS

```
az aks create -g <resource group name> -n <aks name> --location <location has desired GPU> --zones <zone has desired GPU> --generate-ssh-keys
```

## Create GPU nodepool

```
az aks nodepool add --resource-group <resource group name> --cluster-name <aks name> --name <nodepool name> --node-count 1 --skip-gpu-driver-install --node-vm-size <Desire VM type> --node-osdisk-size 2048 --max-pods 110
```

|    Desire VM type                                  | Llama-3-8b    | Llama-3-70b   |
| -------------------------------------------------- | ------------- | ------------- |
| Standard_NC24ads_A100_v4​                           | Optimized     | Not Support   |
| Standard_NC48ads_A100_v4​                           | Optimized     | Not Support   |
| Standard_NC96ads_A100_v4​                           | Optimized     | Not Optimized |
| Standard_ND96asr_A100_v4/Standard_ND96asr_v4​       | Not Optimized | Not Optimized |
| Standard_ND96amsr_A100_v4                          |​ Optimized     | Optimized     |
| Standard_NC40adis_H100_v5 ​                         | Optimized     | Not Support   |
| Standard_NC80adis_H100_v5                          | Optimized     | Not Support   |
| Standard_ND96isr_H100_v5                           | Optimized     | Optimized     |


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