# NemoClaw + Dynamo on AKS (Nemotron‑3 Super FP8)

This workshop shows how to deploy **NemoClaw agents** that use **NVIDIA Dynamo inference** on an AKS cluster.

The goal is simple:

- Deploy Dynamo inference on GPU nodes
- Deploy NemoClaw agents that call the Dynamo endpoint
- Run a basic inference workflow

The install script handles most of the setup.

---

# Prerequisites

You should already have:

- Azure subscription
- AKS cluster with GPU node pool
- kubectl configured
- Docker installed
- Azure Container Registry (ACR)

You will also need access to the Nemotron‑3 Super model weights.

---

# Architecture (high level)

The system has two parts:

1. **Inference plane**
   - Dynamo runs the Nemotron‑3 Super FP8 model
   - Provides the inference API

2. **Application plane**
   - NemoClaw agents
   - Sends requests to Dynamo

---

# Step 1 — Clone the repository

```
git clone https://github.com/NVIDIA/nim-deploy.git
cd nim-deploy/cloud-service-providers/azure/workshops/aks-nemoclaw
```

---

# Step 2 — Configure environment variables

Set your Azure registry and cluster values.

Example:

```
export ACR_NAME=<your-acr>
export AKS_CLUSTER=<cluster-name>
```

---

# Step 3 — Deploy Dynamo inference

The Dynamo deployment manifests are included in this folder.

Apply them:

```
kubectl apply -f dynamo/
```

Wait for pods to start:

```
kubectl get pods
```

You should see Dynamo services running.

---

# Step 4 — Deploy NemoClaw

Run the install script:

```
./deploy_nemoclaw_k8s.sh
```

This script will:

- build the NemoClaw container
- push it to ACR
- deploy the Kubernetes manifests
- connect NemoClaw to the Dynamo endpoint

---

# Step 5 — Verify deployment

Check that the services are running:

```
kubectl get pods
kubectl get svc
```

Confirm that NemoClaw can reach Dynamo.

---

# Optional: Load balancer access

If you enabled the LoadBalancer service, retrieve the public IP:

```
kubectl get svc
```

Use the external address to access the gateway.

---

# Troubleshooting

Common issues:

GPU pods not scheduling
→ check node pool and GPU quota

Image pull failures
→ verify ACR login

Dynamo endpoint unreachable
→ check service name and port

---

# Notes

This workshop focuses on the deployment workflow.

The full install automation is implemented in:

```
deploy_nemoclaw_k8s.sh
```
