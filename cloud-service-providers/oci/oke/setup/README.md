# Setup OCI Kubernetes Engine (OKE)

The key to creating Oracle Kubernetes Engine (OKE) for NIM is to create a proper GPU node pool. The following steps will guide you through the process.

## Connect to OCI

1. Log in to your Oracle Cloud Infrastructure (OCI) Console.
2. Select the appropriate compartment where you want to create the OKE cluster.

## Identify GPU needed for NIM

- Refer to the NIM documentation to identify the NVIDIA GPU you [need](https://docs.nvidia.com/nim/large-language-models/latest/support-matrix.html). Here is also a list of available [OKE NVIDIA GPU node shapes](https://docs.oracle.com/en-us/iaas/Content/Compute/References/computeshapes.htm#vm-gpu).


## Confirm the GPU availability in 

Use the OCI CLI to search for GPU availability:

   ```bash
   oci compute shape list --region <region-name> --compartment-id <your-compartment-id> --all --query 'data[*].shape' --output json | jq -r '.[]' | grep -i 'gpu'
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

## Create GPU nodepool on existing OKE cluster

1. For an existing OKE cluster, navigate to the **Node Pools** section.
2. Click **Add Node Pool** and configure:
   - **Name**: Provide a name for the node pool.
   - **Compartment**: Select the appropriate compartment.
   - **Version**: the Kubernetes version of the nodes - defaults to current cluster version.
   - **Node Placement Configuration** - select Availability Domain and Worker node subnet.
   - **Node Shape**: Select the desired GPU-enabled shape.
   - **Node Image**: is automatically populated with an OEL GPU image which you can change to a different version.
   - **Node Count**: Set the number of nodes (adjust according to your needs).
   - **Additional Configuration**: Customize as needed (e.g., OS disk size, SSH keys).
3. Click **Create Node Pool**.

## Connect to OKE

1. Install the OCI CLI if you haven't already.
2. Retrieve the OKE cluster credentials using the Access Cluster buton in the console Cluster details page:

   ```bash
   oci ce cluster create-kubeconfig --cluster-id <cluster OCID> --file $HOME/.kube/config --region <region> --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT
   ```

3. Verify the connection to your OKE cluster:

   ```bash
   kubectl get nodes
   ```
