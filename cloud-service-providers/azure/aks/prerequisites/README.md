# Pre-requirement

The GPU nodepool should have GPU and GPU driver meet NIM minimum requirement.  This is only achievable via a preview cli extension.

Following is the detail instructions to install from a bash. 

## Install Azure CLI

```
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```
For more detail, Please reference this [link.](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)

## Install AKS Preview extension

```
az extension add --name aks-preview
az extension update --name aks-preview
```

For more detail, Please reference this [link.](https://learn.microsoft.com/en-us/azure/aks/draft)

## Install kubectl

```
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
```

## Install helm

```
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

## Next step

![Continue to AKS creation](../setup/README.md)