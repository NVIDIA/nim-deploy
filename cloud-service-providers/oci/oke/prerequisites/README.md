### OKE Prerequisites

This list summarizes the key prerequisites you need to set up before deploying an OKE cluster on OCI.

- **OCI Account and Tenancy**:
  - Ensure you have an OCI account with the necessary permissions.
  - Set up a compartment for your Kubernetes cluster.

- **Networking**:
  - Create a Virtual Cloud Network (VCN) with appropriate subnets.
  - Ensure internet gateway, NAT gateway, and service gateway are configured.
  - Set up route tables and security lists for network traffic.

- **IAM Policies**:
  - Define IAM policies to allow OKE service to manage resources in your compartment.
  - Grant required permissions to users or groups managing the Kubernetes cluster.

- **Service Limits**:
  - Verify that your tenancy has sufficient service limits for compute instances, block storage, and other required resources.

- **CLI and SDK Tools**:
  - Install and configure the OCI CLI for managing OKE.
  - Optionally, set up OCI SDKs for automating tasks.

- **Kubernetes Version**:
  - Decide on the Kubernetes version to deploy, ensuring compatibility with your applications and OCI features.

- **API Endpoint**:
  - Choose between the public or private endpoint for the Kubernetes API server, based on your security requirements.

For more details, please reference this [link.](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengprerequisites.htm)


## Install OCI CLI

```
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
```

For more details, please reference this [link.](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)

## Install kubectl

```
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
```

For more details, please reference this [link.](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/)

## Install Helm

```
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
```

For more details, please reference this [link.](https://helm.sh/docs/intro/install/)

## Next step

![Continue to OKE creation](../setup/README.md)