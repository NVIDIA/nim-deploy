# Pre-requirement

The keys to create AKS for NIM is to create proper GPU nodepool.  The proper GPU nodepool should have up to date driver.  This is only achievable via a preview cli extension.
We cannot create AKS via Azure Portal GUI and we need to create it using CLI.  We need to setup our terminal with a several cli to perform the AKS creation.  Following is the detail instructions.

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


## Install NGC CLI

```
wget --content-disposition https://api.ngc.nvidia.com/v2/resources/nvidia/ngc-apps/ngc_cli/versions/3.44.0/files/ngccli_linux.zip -O ngccli_linux.zip && unzip ngccli_linux.zip
find ngc-cli/ -type f -exec md5sum {} + | LC_ALL=C sort | md5sum -c ngc-cli.md5
sha256sum ngccli_linux.zip
chmod u+x ngc-cli/ngc
echo "export PATH=\"\$PATH:$(pwd)/ngc-cli\"" >> ~/.bash_profile && source ~/.bash_profile
ngc config set
```

For more detail, Please reference this [link.](https://org.ngc.nvidia.com/setup/installers/cli)

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