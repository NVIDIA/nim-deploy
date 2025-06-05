# NVIDIA NIM Deployment on Oracle Kubernetes Engine (OKE)

This guide provides step-by-step instructions for deploying NVIDIA NIM (NVIDIA Inference Microservices) on Oracle Cloud Infrastructure (OCI) using Oracle Kubernetes Engine (OKE) and GPU instances. NIM allows you to easily deploy and serve AI models like LLaMA 3 with production-ready APIs, scalability, and GPU optimization.

---

## 📋 Prerequisites

Before starting the deployment process, ensure you have the following:

- An active OCI account with appropriate permissions  
- OCI CLI installed and configured on your local machine  
- NVIDIA NGC API key (from [NGC](https://ngc.nvidia.com)) to access NVIDIA's container registry  
- Helm (version 3.x) installed on your local machine for deploying Kubernetes applications  
- Access to the [`nim-deploy`](https://github.com/NVIDIA/nim-deploy) GitHub repo for reference materials  

---

### 🛡️ IAM Policy Requirements

The deployment requires specific OCI Identity and Access Management (IAM) permissions. Ensure your user/group has the following permissions (either directly or via dynamic groups):

```text
Allow group <GROUP_NAME> to manage instance-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to manage cluster-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to manage virtual-network-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to use subnets in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to manage secret-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to use instance-configurations in compartment <COMPARTMENT_NAME>
```

You can assign these permissions through OCI IAM policies or by using predefined roles like "OKE Cluster Administrator" combined with "Network Administrator" and "Compute Instance Administrator" for your compartment.

---

## 🧱 Infrastructure Setup

This section covers the steps to prepare your OCI infrastructure for running NIM. Oracle Cloud offers various GPU options that provide the compute power needed for efficient AI model inference.

### 1. Create a Virtual Cloud Network (VCN)
**Setting up the network foundation for your OKE cluster**

First, set up the networking infrastructure to support your OKE cluster:

- Public Subnet: For OKE worker nodes to allow management access  
- Private Subnet (optional): For internal services that don't need direct internet access  
- NAT Gateway or Internet Gateway (if using public IPs): For outbound internet connectivity  
- Ensure ports `443` and `8000` are open in your NSG or security list for specific trusted IP ranges

These network components establish the foundation for your cluster's connectivity.

When configuring security lists or network security groups, use restricted CIDR blocks instead of opening to all IPs:

```bash
# Example of restricting access to specific trusted IPs or corporate network
oci network security-list update \
  --security-list-id <SECURITY_LIST_OCID> \
  --ingress-security-rules '[
    {
      "protocol":"6",
      "source":"10.0.0.0/8",
      "tcpOptions":{"destinationPortRange":{"min":8000,"max":8000}},
      "isStateless":false
    },
    {
      "protocol":"6",
      "source":"192.168.0.0/16",
      "tcpOptions":{"destinationPortRange":{"min":443,"max":443}},
      "isStateless":false
    }
  ]'
```

Replace the CIDR blocks (`10.0.0.0/8`, `192.168.0.0/16`) with your specific corporate network ranges or trusted IP addresses.

---

### 2. Create a NAT Gateway (Recommended)
**Enabling secure outbound internet access for private resources**

A NAT Gateway provides outbound internet access for resources in private subnets while maintaining security:

```bash
oci network route-rule add --route-table-id <ROUTE_TABLE_OCID> \
  --destination 0.0.0.0/0 \
  --network-entity-id <NAT_GATEWAY_OCID>
```

This allows your cluster nodes to download containers and model weights while maintaining a secure network posture.

---

### 3. Setup Internet Gateway (Alternative)
**Providing direct internet connectivity for public-facing resources**

If you prefer to use public subnets with direct internet access, you can set up an Internet Gateway instead:

```bash
# Create Internet Gateway
oci network internet-gateway create \
  --compartment-id <COMPARTMENT_OCID> \
  --vcn-id <VCN_OCID> \
  --is-enabled true \
  --display-name "NIM-InternetGateway"

# Get the Internet Gateway OCID
INTERNET_GATEWAY_OCID=$(oci network internet-gateway list \
  --compartment-id <COMPARTMENT_OCID> \
  --vcn-id <VCN_OCID> \
  --query "data[?contains(\"display-name\",'NIM-InternetGateway')].id" \
  --raw-output)

# Add route rule to the public subnet's route table
oci network route-table update \
  --rt-id <PUBLIC_ROUTE_TABLE_OCID> \
  --route-rules '[{"destination": "0.0.0.0/0", "destinationType": "CIDR_BLOCK", "networkEntityId": "'$INTERNET_GATEWAY_OCID'"}]'
```

Using an Internet Gateway provides:
- Direct inbound and outbound internet connectivity
- Simplifies access to external resources
- Eliminates the need for proxies in many cases
- Useful for development environments or when security requirements allow direct connectivity

However, Internet Gateways expose your nodes to the public internet, so ensure proper security groups and network security lists are configured with restricted CIDR blocks.

---

### 4. Create an Instance Configuration
**Defining the VM template for your GPU nodes**

This step creates a template that defines the hardware and software configuration for your GPU instances, including shape, image, network settings, and SSH access:

```bash
oci compute-management instance-configuration create \
--compartment-id <COMPARTMENT_OCID> \
--instance-details '{
  "instanceType": "compute",
  "launchDetails": {
    "availabilityDomain": "<AVAILABILITY_DOMAIN>",
    "compartmentId": "<COMPARTMENT_OCID>",
    "shape": "BM.GPU.A100-v2.8",
    "sourceDetails": {
      "sourceType": "image",
      "imageId": "<IMAGE_OCID>"
    },
    "metadata": {
      "ssh_authorized_keys": "<YOUR_SSH_PUBLIC_KEY>"
    },
    "createVnicDetails": {
      "subnetId": "<SUBNET_OCID>",
      "assignPublicIp": true
    }
  }
}' \
--profile OCI
```

---

### 5. Create the Cluster Network with GPU Nodes
**Creating your compute cluster with GPU resources in one step**

This step creates a cluster network with the specified GPU nodes, which will be used to run your NIM deployment:

```bash
oci compute-management cluster-network create \
--compartment-id <COMPARTMENT_OCID> \
--instance-pools file://instance_pools.json \
--placement-configuration file://placement_config.json \
--display-name "A100-Cluster-NIM" \
--profile OCI
```

#### 📄 `instance_pools.json`

```json
[
  {
    "instanceConfigurationId": "<INSTANCE_CONFIGURATION_OCID>",
    "size": 1,
    "displayName": "NIM-Pool",
    "availabilityDomain": "<AVAILABILITY_DOMAIN>",
    "faultDomain": "FAULT-DOMAIN-1"
  }
]
```

#### 📄 `placement_config.json`

```json
{
  "availabilityDomain": "<AVAILABILITY_DOMAIN>",
  "placementConstraint": "PACKED_DISTRIBUTION_MULTI_BLOCK",
  "primaryVnicSubnets": {
    "subnetId": "<SUBNET_OCID>"
  }
}
```

This creates GPU-equipped nodes in a cluster configuration.

---

## 6. Connect to Your Cluster
**Streamlining authentication with direct kubectl configuration**

There are two ways to connect to your OKE cluster:

### Option A: Direct kubectl Configuration (Recommended)
**Setting up persistent access to your cluster**

For a more seamless experience that allows using `kubectl` directly:

```bash
# Configure kubectl with OCI authentication
oci ce cluster create-kubeconfig --cluster-id <YOUR_CLUSTER_OCID> --file $HOME/.kube/config --region <YOUR_REGION> --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT --profile oci --auth security_token
```

This command:
- Creates a persistent kubeconfig file with token-based authentication
- Adds the necessary authentication parameters to the kubeconfig
- Sets up secure access using your OCI security token
- Allows direct use of standard kubectl commands

> **Note on OCI Authentication:** The OCI security token has a maximum lifetime of 60 minutes. When your token expires (usually after closing your laptop or leaving it idle for too long), you will need to re-authenticate.
> 
> To refresh your authentication:
> 
> **Quick refresh command:**
> 
> ```bash
> oci session authenticate --profile oci && oci ce cluster create-kubeconfig --cluster-id <YOUR_CLUSTER_OCID> --file $HOME/.kube/config --region <YOUR_REGION> --token-version 2.0.0 --kube-endpoint PUBLIC_ENDPOINT --profile oci --auth security_token
> ```
> 
> 1. Run `oci session authenticate --profile oci`
> 2. Then recreate the kubeconfig with the same command as above
> 
> Unfortunately, OCI does not support tokens with lifetimes longer than 60 minutes, so periodic re-authentication is required.


Test your connection to verify it works:

```bash
kubectl get nodes
```

**Expected Output:**
```
NAME         STATUS   ROLES   AGE   VERSION
10.0.10.12   Ready    node    12h   v1.32.1
10.0.10.40   Ready    node    17h   v1.32.1
```

You should see a list of your cluster's nodes. This confirms that the configuration is working correctly and you have direct access to your cluster.

### Option B: Wrapper Script (Legacy Method)
**Using a helper script for temporary access**

If you prefer using a wrapper script (not recommended for ongoing use):

```bash
# Create a wrapper script for kubectl with OCI authentication
cat > oke-connect.sh << 'EOF'
#!/bin/bash

# Generate token
oci ce cluster generate-token \
  --cluster-id <YOUR_CLUSTER_OCID> \
  --region <YOUR_REGION> \
  --profile oci \
  --auth security_token > /tmp/k8s_token.json

# Extract token
TOKEN=$(cat /tmp/k8s_token.json | grep -o '"token": "[^"]*' | cut -d'"' -f4)

# Use token with kubectl
kubectl --token=$TOKEN "$@" 
EOF

# Make the script executable
chmod +x oke-connect.sh
```

Test with:
```bash
./oke-connect.sh get nodes
```

## 7. Set Up the NIM Namespace and NGC API Key
**Creating a dedicated namespace and securing your NGC credentials**

Create a dedicated namespace for NIM and store your NGC API key as a Kubernetes secret:

```bash
# Create namespace
kubectl create namespace nim
```

**Expected Output:**
```
namespace/nim created
```

```bash
# Get your NGC API key
NGC_API_KEY=<YOUR_NGC_API_KEY>

# Create a secret for pulling images from NGC
kubectl create secret docker-registry ngc-registry \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password=$NGC_API_KEY \
  -n nim
```

**Expected Output:**
```
secret/ngc-registry created
```

This isolates your NIM deployment from other applications in the cluster and securely stores your NGC API key, which is needed to pull NVIDIA's container images.

## 8. Install Node Feature Discovery (NFD) (Optional but recommended for an easier setup)
**Enabling Kubernetes to identify GPU-equipped nodes**

NFD is a critical component that allows Kubernetes to identify and label nodes with their hardware capabilities, particularly GPUs:

```bash
# Add the NFD Helm repository
helm repo add nfd https://kubernetes-sigs.github.io/node-feature-discovery/charts
```

**Expected Output:**
```
"nfd" has been added to your repositories
```

```bash
helm repo update
```

**Expected Output:**
```
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "nfd" chart repository
Update Complete. ⎈Happy Helming!⎈
```

```bash
# Install NFD using Helm
helm install nfd nfd/node-feature-discovery --namespace kube-system
```

**Expected Output:**
```
NAME: nfd
LAST DEPLOYED: Thu Jun 4 12:23:45 2023
NAMESPACE: kube-system
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The Node Feature Discovery has been installed. Check its status by running:
  kubectl --namespace kube-system get pods -l "app.kubernetes.io/instance=nfd"
```

```bash
# Verify NFD is running
kubectl get pods -n kube-system | grep nfd
```

**Expected Output:**
```
nfd-master-85b844d55-zxj7p                   1/1     Running   0          3m22s
nfd-worker-4hk8f                             1/1     Running   0          3m22s
nfd-worker-6zrwj                             1/1     Running   0          3m22s
nfd-worker-nczl8                             1/1     Running   0          3m22s
```

NFD automatically detects the NVIDIA GPUs in your cluster and adds appropriate labels to the nodes. Without this, Kubernetes wouldn't know which nodes have GPUs available.

## 9. Install NVIDIA NIM Operator
**Deploying the custom resource controller for NIM services**

The NIM Operator manages the lifecycle of NIM services in your cluster:

```bash
# Add NVIDIA Helm repository
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
```

**Expected Output:**
```
"nvidia" has been added to your repositories
```

```bash
helm repo update
```

**Expected Output:**
```
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "nvidia" chart repository
Update Complete. ⎈Happy Helming!⎈
```

```bash
# Install NVIDIA NIM Operator
helm install --namespace nim nvidia-nim-operator nvidia/k8s-nim-operator
```

**Expected Output:**
```
NAME: nvidia-nim-operator
LAST DEPLOYED: Thu Jun 4 12:34:56 2023
NAMESPACE: nim
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The NVIDIA NIM Operator has been installed. Check its status by running:
  kubectl --namespace nim get pods -l "app.kubernetes.io/instance=nvidia-nim-operator"
```

This operator extends Kubernetes with custom resources for NIM deployments, making it easier to manage model deployments and their configurations.

## 10. Enable Internet Access via Proxy (Optional)
**Deploying a proxy solution for restricted network environments**

In enterprise environments, OKE clusters often lack direct internet access. If needed, set up a proxy to allow model downloads:

```bash
# Navigate to the Helm chart directory
cd nim-deploy/helm

# Install Squid proxy using Helm
helm install squid-proxy ./squid-proxy --namespace nim
```

**Expected Output:**
```
NAME: squid-proxy
LAST DEPLOYED: Thu Jun 4 12:45:12 2023
NAMESPACE: nim
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The Squid proxy has been deployed to your cluster.
```

This deploys a Squid proxy in your cluster that uses hostNetwork to bypass network restrictions. The NIM services will be configured to use this proxy for downloading model files from NVIDIA's servers.

## 11. Deploy LLaMA 3-8B Model Using Helm
**Installing and configuring the LLaMA model with persistent storage**

Now it's time to deploy the actual LLaMA 3-8B model using Helm:

```bash
# Add NVIDIA Helm repository if not already added
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
helm repo update
```

**Expected Output:**
```
"nvidia" already exists with the same configuration, skipping
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "nvidia" chart repository
Update Complete. ⎈Happy Helming!⎈
```

```bash
# Install the NIM service using Helm with the provided values.yaml
helm --namespace nim install llama3-8b nvidia/nim-llm -f values.yaml
```

**Expected Output:**
```
NAME: llama3-8b
LAST DEPLOYED: Thu Jun 4 13:01:23 2023
NAMESPACE: nim
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The LLaMA 3-8B model has been deployed to your cluster.
It might take several minutes for the model to download and initialize.
Check the status with: kubectl --namespace nim get pods -l "app=llama3-8b"
```

> **Note:** You'll need to create a `values.yaml` file with appropriate configuration for your deployment. A sample `values.yaml` file is provided below:
> 
> ```yaml
> # Sample values.yaml for LLaMA 3-8B deployment
> image:
>   repository: nvcr.io/nim/meta/llama3-8b-instruct
>   tag: "1.0.0"
> 
> resources:
>   limits:
>     nvidia.com/gpu: 1
>   requests:
>     nvidia.com/gpu: 1
>     memory: "16Gi"
>     cpu: "4"
> 
> persistence:
>   size: "50Gi"
>   storageClass: "oci-bv"
> 
> service:
>   type: LoadBalancer
>   port: 8000
> ```
> 
> Adjust the resource requests and limits according to your specific GPU type and model requirements.

The `values.yaml` file includes:
- Model configuration (LLaMA 3-8B by default)
- GPU resource allocation based on your selected GPU type
- Persistent storage for model files
- Health probes for monitoring
- Service exposure via LoadBalancer

The persistence configuration is critical to ensure that model weights are stored persistently. For larger models like LLaMA 3-70B, increase the size to at least 100Gi or more.

The deployment will take several minutes as it downloads the model weights and initializes the service.

## 12. Monitor Deployment Status
**Verifying the successful deployment of your model**

Monitor the deployment to ensure everything is running correctly:

```bash
# Check the pods
kubectl get pods -n nim
```

**Expected Output (initial state):**
```
NAME                        READY   STATUS              RESTARTS   AGE
llama3-8b-76c9f6b5f-8x4jz   0/1     ContainerCreating   0          2m15s
```

**Expected Output (after model download):**
```
NAME                        READY   STATUS    RESTARTS   AGE
llama3-8b-76c9f6b5f-8x4jz   1/1     Running   0          12m45s
```

```bash
# Check the services
kubectl get svc -n nim
```

**Expected Output:**
```
NAME        TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)          AGE
llama3-8b   LoadBalancer   10.96.157.218    <EXTERNAL-IP>    8000:30450/TCP   15m
```

```bash
# Check deployment status
kubectl describe pod -n nim -l app=llama3-8b
```

**Expected Output (abbreviated):**
```
Name:         llama3-8b-76c9f6b5f-8x4jz
Namespace:    nim
Priority:     0
Node:         10.0.10.17/10.0.10.17
Start Time:   Thu, 04 Jun 2023 13:01:45 -0500
...
Status:       Running
...
Conditions:
  Type              Status
  Initialized       True 
  Ready             True 
  ContainersReady   True 
  PodScheduled      True 
...
Events:
  Type    Reason     Age   Message
  ----    ------     ----  -------
  Normal  Scheduled  14m   Successfully assigned nim/llama3-8b-76c9f6b5f-8x4jz to 10.0.10.17
  Normal  Pulling    14m   Pulling image "nvcr.io/nim/meta/llama3-8b-instruct:1.0.0"
  Normal  Pulled     12m   Successfully pulled image "nvcr.io/nim/meta/llama3-8b-instruct:1.0.0"
  Normal  Created    12m   Created container llama3-8b
  Normal  Started    12m   Started container llama3-8b
```

These commands help you verify that:
1. The pod is running correctly
2. The service has been created with the correct configuration
3. There are no errors in the deployment

The pod may initially show a status of "ContainerCreating" as it downloads the large model files.

## 13. Accessing the Model via LoadBalancer
**Establishing external access for production use**

The LoadBalancer service provides a stable, externally accessible endpoint for your model:

```bash
# Get the LoadBalancer service details
kubectl get svc -n nim
```

**Expected Output:**
```
NAME        TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)          AGE
llama3-8b   LoadBalancer   10.96.157.218    <EXTERNAL-IP>    8000:30450/TCP   15m
```

Look for the `llama3-8b` service with a TYPE of `LoadBalancer`. The `EXTERNAL-IP` column will show the assigned IP address. Once available, you can access the model directly through this IP:

```bash
# Test the health endpoint
curl http://<EXTERNAL-IP>:8000/v1/health/ready
```

**Expected Output:**
```
{"status":"ready"}
```

```bash
# Test a chat completion
curl -X POST http://<EXTERNAL-IP>:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Hello, tell me briefly about NVIDIA."}
    ],
    "model": "meta/llama3-8b-instruct",
    "max_tokens": 150
  }'
```

**Expected Output (abbreviated):**
```json
{
  "id": "cdee0dec-a12c-4de3-9061-285def95f4b1",
  "object": "chat.completion",
  "created": 1717710883,
  "model": "meta/llama3-8b-instruct",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "NVIDIA is a leading technology company specializing in designing and manufacturing graphics processing units (GPUs) and artificial intelligence systems. Founded in 1993, NVIDIA initially focused on producing GPUs for gaming but has since expanded into various fields including data centers, autonomous vehicles, robotics, and AI computing. The company's innovations have been crucial for advancements in deep learning, scientific computing, and visual computing applications."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 28,
    "completion_tokens": 84,
    "total_tokens": 112
  }
}
```

The LoadBalancer provides several benefits for production use:
1. Manages traffic distribution to your pods
2. Provides a consistent access point
3. Handles pod failures and restarts transparently
4. Offers better stability than port forwarding

Note that it may take several minutes for the LoadBalancer to provision and for the external IP to become accessible. If the readiness probe is failing, the LoadBalancer might not route traffic to the pod until it's ready.

## 14. Alternative: Test the Model via Port Forwarding
**Creating a secure tunnel to access your model during development**

> **Note:** This alternative method is only needed if your LoadBalancer is not yet provisioned or if you're working in an environment where LoadBalancer services aren't available.

You can test the model locally using port forwarding, which creates a secure tunnel between your local machine and the pod:

```bash
# Set up port forwarding
kubectl port-forward -n nim pod/$(kubectl get pods -n nim -l app=llama3-8b -o jsonpath='{.items[0].metadata.name}') 8000:8000 &
```

**Expected Output:**
```
Forwarding from 127.0.0.1:8000 -> 8000
Forwarding from [::1]:8000 -> 8000
```

```bash
# Test the health endpoint
curl http://localhost:8000/v1/health/ready
```

**Expected Output:**
```
{"status":"ready"}
```

```bash
# Test a chat completion
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Hello, tell me about NVIDIA."}
    ],
    "model": "meta/llama3-8b-instruct"
  }'
```

**Expected Output (abbreviated):**
```json
{
  "id": "a57b41f6-8321-4e7c-9cb3-4851df7a6d22",
  "object": "chat.completion",
  "created": 1717710985,
  "model": "meta/llama3-8b-instruct",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "NVIDIA is a technology company that specializes in designing and manufacturing graphics processing units (GPUs) and other computing hardware. Founded in 1993, NVIDIA initially focused on creating graphics cards for gaming and professional visualization. Over time, they've expanded their focus to include artificial intelligence, high-performance computing, autonomous vehicles, and robotics.\n\nSome key aspects of NVIDIA:\n\n1. GPU Technology: NVIDIA is best known for their GPUs, which were originally designed for rendering graphics but have become essential for parallel processing tasks like AI training and inference.\n\n2. CUDA Platform: They developed CUDA, a parallel computing platform that allows developers to use NVIDIA GPUs for general-purpose processing.\n\n3. Data Center Solutions: NVIDIA provides hardware and software for data centers, including their DGX systems for AI research and HGX platforms for cloud computing.\n\n4. Autonomous Vehicles: Their DRIVE platform is used for developing self-driving car technology.\n\n5. Professional Visualization: Their Quadro/RTX line serves professionals in fields like design, animation, and scientific visualization.\n\nNVIDIA has become particularly important in the AI revolution, as their GPUs have proven essential for training and running large AI models."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 24,
    "completion_tokens": 231,
    "total_tokens": 255
  }
}
```

> **Troubleshooting Note:** Port forwarding can be unstable and may disconnect unexpectedly. If you experience "lost connection to pod" errors or "address already in use" messages, you may need to kill existing port-forward processes (`pkill -f "port-forward"`) before trying again.

## Conclusion
**Summary of your NIM deployment on OKE**

You now have a working NIM deployment on OKE serving the LLaMA 3-8B model. The deployment is accessible both via port forwarding for development/testing purposes and through a LoadBalancer service for more permanent external access.

This setup provides you with:
1. A scalable, production-ready LLM deployment
2. GPU-accelerated inference for fast responses
3. An OpenAI-compatible API for easy integration with applications
4. Persistent storage for model files

Remember to regularly check your OCI authentication status if you encounter connection issues, as session tokens expire after a period of time.

## Infrastructure Creation Summary

In this guide, the infrastructure setup process follows these key steps:

1. Create the networking components (VCN, subnets, gateways)
2. Define an instance configuration template for the GPU-equipped VMs
3. Create a cluster network that instantiates the GPU nodes based on the template
4. Deploy NIM services using Helm charts onto the cluster
5. Configure persistent storage for model weights

---

## ✅ Deployment Checklist

Ensure the following are complete before proceeding with inference:

- [ ] **OKE cluster** is active and accessible  
- [ ] **GPU node pool** (e.g., A100, L40S) is ready and healthy  
- [ ] **NAT Gateway** or other outbound internet access is configured  
- [ ] **NGC secret** is created in the `nim` namespace  
- [ ] **Helm chart** deployed successfully (`helm list -n nim`)  
- [ ] **NIM service** is reachable on `port 8000`

### Verification Steps

Use these commands to verify your deployment is correctly configured:

```bash
# Check if your OKE cluster is accessible
kubectl get nodes
```

```bash
# Verify GPU node labels are detected
kubectl describe nodes | grep nvidia.com/gpu
```

```bash
# Confirm NGC secret exists
kubectl get secret -n nim ngc-registry
```

```bash
# Verify Helm chart is installed
helm list -n nim
```

```bash
# Check NIM service health
SERVICE_IP=$(kubectl get svc -n nim llama3-8b -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://${SERVICE_IP}:8000/v1/health/ready
```

These verification steps should all return successful responses to confirm your deployment is ready.

---

## 🎮 GPU Compatibility

### 🔢 Recommended GPU Shapes

| Model Size | Recommended Shapes |
|------------|--------------------|
| 8B         | `BM.GPU.A10G.2`, `BM.GPU.L40.2` |
| 13B        | `BM.GPU.L40.2`, `BM.GPU.A100-v2.8` |
| 30B        | `BM.GPU.A100-v2.8`, `BM.GPU.H100.8` |
| 70B+       | `BM.GPU.H100.8`, `BM.GPU.H200.8` |

### ✅ Supported OCI GPUs for NIM

| GPU Model    | Memory   | Architecture | NIM Compatibility | Best For                       |
|--------------|----------|--------------|-------------------|--------------------------------|
| H200         | 141 GB   | Hopper       | ✅ Excellent       | Max throughput, large models   |
| H100         | 80 GB    | Hopper       | ✅ Excellent       | 30B–70B models, production use |
| A100         | 80 GB    | Ampere       | ✅ Excellent       | Most models, stable baseline   |
| L40S         | 48 GB    | Lovelace     | ✅ Good            | Mid-size models (7B–30B)       |
| A10G         | 24 GB    | Ampere       | ✅ Limited         | Small models (7B–13B)          |

---


## 🚨 Troubleshooting

This section outlines the most common issues you might encounter when deploying or running NIM on OKE, along with actionable steps to resolve them.

---

### 🔧 Common Problems & Fixes

#### 🔁 Pod in CrashLoopBackOff

```bash
kubectl logs -n nim <pod-name>
```

**Expected Output (for NGC API key issues):**
```
Error: Failed to download model files: Authentication failed. Please check your NGC API key.
```

**Possible causes:**

* Invalid NGC API key
* No outbound internet access
* Insufficient GPU resources

---

#### 🌐 Hanging curl / No Response

```bash
kubectl run curl-test -n nim --image=ghcr.io/curl/curlimages/curl:latest \
  -it --rm --restart=Never -- \
  curl https://api.ngc.nvidia.com
```

**Expected Output (successful connection):**
```
<html>
<head><title>301 Moved Permanently</title></head>
<body>
<center><h1>301 Moved Permanently</h1></center>
<hr><center>nginx</center>
</body>
</html>
```

**If this fails:** Outbound internet is blocked. Set up a NAT Gateway or configure proxy settings.

---

#### 🎮 GPU Not Detected

```bash
kubectl describe nodes | grep nvidia.com/gpu
```

**Expected Output:**
```
                    nvidia.com/gpu:             8
                    nvidia.com/gpu.memory:      81920M
                    nvidia.com/gpu.product:     A100-SXM4-80GB
```

**Possible causes:**

* Node Feature Discovery (NFD) not installed
* GPU drivers not properly installed on nodes
* Incorrect GPU shape configuration

---

#### 🔐 Authentication Issues

```bash
# Method 1: Session authentication
oci session authenticate
```

**Expected Output:**
```
Enter a password or web browser will be opened to https://login.us-ashburn-1.oraclecloud.com/...
```

```bash
# Method 2: Validate existing session
oci session validate --profile oci
```

**Expected Output (valid session):**
```
Session is valid
```

**Expected Output (expired session):**
```
Session is invalid or expired
```

Session tokens typically expire after a few hours. Refresh if needed.

---

#### 🌍 Internet Connectivity Problems

```bash
# Test general internet connectivity from within the cluster
kubectl run test-connectivity --image=alpine -n nim --rm -it -- sh -c "apk add curl && curl -I https://ngc.nvidia.com"
```

**Expected Output:**
```
HTTP/1.1 200 OK
Date: Mon, 01 Jun 2023 12:34:56 GMT
Server: nginx
Content-Type: text/html; charset=UTF-8
Connection: keep-alive
Cache-Control: no-cache
```

**Troubleshooting steps:**

1. **If DNS resolution fails:** Check DNS server configuration in the cluster
   ```bash
   kubectl run dns-test -n nim --rm -it --image=alpine -- nslookup ngc.nvidia.com
   ```

2. **If proxy is needed:** Configure HTTP_PROXY and HTTPS_PROXY environment variables in your pod spec
   ```yaml
   env:
   - name: HTTP_PROXY
     value: "http://proxy.example.com:8080"
   - name: HTTPS_PROXY
     value: "http://proxy.example.com:8080"
   - name: NO_PROXY
     value: "localhost,127.0.0.1,10.96.0.0/12,192.168.0.0/16"
   ```

3. **If NAT Gateway isn't working:** Verify your route table configurations
   ```bash
   oci network route-table get --rt-id <ROUTE_TABLE_OCID>
   ```

4. **For security group issues:** Ensure outbound traffic is allowed on ports 443 and 80
   ```bash
   oci network security-list list --subnet-id <SUBNET_OCID>
   ```
