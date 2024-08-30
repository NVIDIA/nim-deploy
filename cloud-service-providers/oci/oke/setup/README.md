# Setup OCI Kubernetes Engine (OKE)

The key to creating Oracle Kubernetes Engine (OKE) for NIM is to create a proper GPU node pool. The following steps will guide you through the process.

## Connect to OCI

1. Log in to your Oracle Cloud Infrastructure (OCI) Console.
2. Select the appropriate compartment where you want to create the OKE cluster.

## Identify GPU needed for NIM

- Refer to the NIM documentation to identify the NVIDIA GPU you [need](https://docs.nvidia.com/nim/large-language-models/latest/support-matrix.html). Here is also a list of available [OKE NVIDIA GPU node shapes](https://docs.oracle.com/en-us/iaas/Content/Compute/References/computeshapes.htm#vm-gpu).


## Find the Region with the Desired GPU

1. Go to the OCI Console and navigate to the "Shape Availability" section to find the region that supports the desired GPU shape.
2. Alternatively, use the OCI CLI to search for GPU availability:

   ```bash
   oci compute shape list --all
   ```

   Cross-reference with the [OCI Regions](https://www.oracle.com/cloud/data-regions.html) to select the best region.

## Request Quota

Ensure you have the necessary service limits (quota) for the GPU shapes. If needed, request an increase via the OCI Console:

1. Navigate to **Governance and Administration** > **Limits, Quotas, and Usage**.
2. Select **Request Service Limit Increase** for the relevant GPU shapes.

## Create OKE

1. In the OCI Console, navigate to **Developer Services** > **Kubernetes Clusters** > **OKE Clusters**.
2. Click **Create Cluster** and select **Start with Quick Create**.
3. Configure the following:
   - **Name**: Provide a name for your cluster.
   - **Compartment**: Select the appropriate compartment.
   - **Kubernetes Version**: Choose the latest stable version.
   - **Shape**: Choose a shape with the desired GPU (e.g., `BM.GPU.A100.1`, `BM.GPU.A10.1`).
4. Under **Node Pool Configuration**:
   - **Node Pool Name**: Name your node pool.
   - **Shape**: Select the GPU shape identified earlier.
   - **Node Count**: Start with 1 node (adjust as needed).
   - **Node Subnet**: Select a subnet within your VCN.
5. Click **Create Cluster** to start the provisioning process.

## Create GPU nodepool

1. After the cluster is created, navigate to the **Node Pools** section.
2. Click **Add Node Pool** and configure:
   - **Name**: Provide a name for the node pool.
   - **Node Shape**: Select the desired GPU-enabled shape.
   - **Node Count**: Set the number of nodes (adjust according to your needs).
   - **Additional Configuration**: Customize as needed (e.g., OS disk size, SSH keys).
3. Click **Create Node Pool**.

## Connect to OKE

1. Install the OCI CLI if you haven't already.
2. Retrieve the OKE cluster credentials:

   ```bash
   oci ce cluster create-kubeconfig --cluster-id <cluster OCID> --file $HOME/.kube/config --region <region> --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT
   ```

3. Verify the connection to your OKE cluster:

   ```bash
   kubectl get nodes
   ```

## Install GPU Operator (Only if necessary)

**Note:** If you're using an OCI GPU shape that comes with the drivers pre-installed (such as those  having 'GPU' in their names, for example the ones in the `BM.GPU.A100` series), you can skip this section. The GPU drivers are already installed and configured. 

If your chosen shape does not include the GPU drivers, follow the steps below to install the NVIDIA GPU Operator.

1. Add the NVIDIA Helm repository:

   ```bash
   helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --pass-credentials
   helm repo update
   ```

2. Install the GPU Operator in your OKE cluster:

   ```bash
   helm install --create-namespace --namespace gpu-operator nvidia/gpu-operator --wait --generate-name
   ```

3. Monitor the deployment to ensure everything is set up correctly:

   ```bash
   kubectl get pods -n gpu-operator
   ```

Official instructions for the NVIDIA GPU Operator can be found [here](https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html).
