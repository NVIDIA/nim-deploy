NVIDIA NIM Deployment on Oracle Kubernetes Engine (OKE)

This guide provides step-by-step instructions for deploying NVIDIA NIM (NVIDIA Inference Microservices) on Oracle Cloud Infrastructure (OCI) using Oracle Kubernetes Engine (OKE) and A100's. 

**Prerequisites**
	•	An active OCI account
	•	OCI CLI installed and configured
	•	Proper IAM policies for creating required resources (e.g., ContainerEngine, Compute, VCNs, Subnets, Secrets, InstancePools)
	•	NVIDIA NGC API key (available from NGC)
	•	Helm installed on your local machine
	•	Access to NVIDIA’s nim-deploy GitHub repository

**Infrastructure Setup**

1. Create a Virtual Cloud Network (VCN)
	•	Public Subnet: For OKE worker nodes
	•	Private Subnet (optional): For internal services
	•	NAT Gateway or Internet Gateway: If using public IPs
	•	Ensure ports 443 and 8000 are allowed in your Network Security Group (NSG) or Security List if testing locally.

2. Create a NAT Gateway (Recommended)
	•	Create a NAT Gateway in the same VCN
	•	Update your public subnet’s route table:

oci network route-rule add --route-table-id <ROUTE_TABLE_OCID> \
  --destination 0.0.0.0/0 --network-entity-id <NAT_GATEWAY_OCID>

3. Create the OKE Cluster

oci ce cluster create \
  --name NIM-OKE-Cluster \
  --compartment-id <COMPARTMENT_OCID> \
  --vcn-id <VCN_OCID> \
  --kubernetes-version "v1.32.1" \
  --subnet-ids '["<SUBNET_OCID>"]'

4. Add Node Pool

**Provision nodes with shape BM.GPU.A100-v2.8:**

oci ce node-pool create \
  --cluster-id <CLUSTER_OCID> \
  --name NIM-GPU-Pool \
  --node-shape BM.GPU.A100-v2.8 \
  --node-config-details file://node-config.json

Sample node-config.json:

{
  "placementConfigs": [{
    "availabilityDomain": "Uocm:US-ASHBURN-AD-1",
    "subnetId": "<SUBNET_OCID>"
  }],
  "size": 1
}

**Create Secret for NGC API Key**

kubectl create namespace nim
kubectl create secret generic ngc-api -n nim \
  --from-literal=NGC_API_KEY=<your-ngc-api-key>

**Helm Chart Deployment**

Clone the nim-deploy repository and navigate to the Helm chart directory:

git clone https://github.com/NVIDIA/nim-deploy.git
cd nim-deploy/helm

Option 1: Minimal Inline Install

export NGC_API_KEY=<your-ngc-api-key>
helm --namespace nim install my-nim nim-llm/ \
  --set model.ngcAPIKey=$NGC_API_KEY \
  --set persistence.enabled=true

Option 2: Custom values.yaml (Recommended)

**Create the required secrets:**

kubectl -n nim create secret docker-registry registry-secret \
  --docker-server=nvcr.io --docker-username='$oauthtoken' --docker-password=$NGC_API_KEY

kubectl -n nim create secret generic ngc-api \
  --from-literal=NGC_API_KEY=$NGC_API_KEY

Use the provided values.yaml file tailored for Oracle OKE, which includes configurations such as:

image:
  repository: nvcr.io/nim/meta/llama3-8b-instruct
  tag: 1.0.0
imagePullSecrets:
  - name: registry-secret
model:
  name: meta/llama3-8b-instruct
  ngcAPISecret: ngc-api
persistence:
  enabled: true
statefulSet:
  enabled: false
resources:
  limits:
    nvidia.com/gpu: 1

**Deploy using the custom values file:**

helm --namespace nim install my-nim nim-llm/ -f ./values.yaml

Port Forwarding for Local Testing

Once the pod is READY, expose the service locally:

kubectl port-forward svc/my-nim-nim-llm -n nim 8000:8000

**Check readiness:**

curl http://localhost:8000/v1/health/ready

**Sample cURL Test (LLaMA)**

Once the health check is ready, you can test the LLaMA NIM endpoint with a simple prompt:

curl http://localhost:8000/v1/completions \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta/llama3-8b-instruct",
    "prompt": "Write a haiku about Oracle Cloud.",
    "temperature": 0.7,
    "max_tokens": 100
  }'

Example response:

{
  "id": "cmpl-xyz123",
  "object": "text_completion",
  "created": 1717070000,
  "model": "meta/llama3-8b-instruct",
  "choices": [
    {
      "text": "Cloud drifts over peaks, \nOracle powers the skies — \nData flows like wind.",
      "index": 0,
      "finish_reason": "stop"
    }
  ]
}

Note: Ensure your deployed NIM supports meta/llama3-8b-instruct or adjust the model field accordingly.

**Troubleshooting**

Problem: Pod in CrashLoopBackOff
	•	Check logs: kubectl logs -n nim <pod-name>
	•	Common Cause: NGC API key is invalid or outbound internet is blocked.

Problem: Hanging curl or empty reply
	•	Run:

kubectl run curl-test -n nim --image=ghcr.io/curl/curlimages/curl:latest -it --rm --restart=Never -- \
  curl https://api.ngc.nvidia.com

	•	If it fails, your cluster doesn’t have outbound internet. Use a NAT Gateway instead.

**Final Checklist**
	•	OKE Cluster is Active
	•	Node Pool with GPU is Ready
	•	Internet or NAT Gateway is configured
	•	NGC secret is present in nim namespace
	•	Helm deployment is successful
	•	Port forwarding works and health check passes

**Resources**
	•	NVIDIA NIM GitHub
	•	Oracle Cloud Infrastructure Docs
	•	NVIDIA NGC
