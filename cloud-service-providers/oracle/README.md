# NVIDIA NIM Deployment on Oracle Kubernetes Engine (OKE)

This folder contains Kubernetes manifests to deploy NVIDIA's NIM LLM (LLaMA 3) container on Oracle Cloud Infrastructure (OCI) using Oracle Kubernetes Engine (OKE).

---

## 🧠 Model Deployed
- **Name:** `meta/llama3-8b-instruct`
- **Framework:** NVIDIA Inference Microservice (NIM)
- **Inference API:** OpenAI-compatible endpoint (`/v1/chat/completions`)

---

## 🛠️ Prerequisites

- ✅ OCI tenancy with GPU shapes (e.g. BM.GPU.A100)
- ✅ OKE cluster up and running
- ✅ `kubectl` and `helm` configured for your cluster
- ✅ NVIDIA NGC API Key ([get one](https://ngc.nvidia.com/setup/api-key))

---

## 📁 File Structure

cloud-service-providers/oracle/oke/
├── prerequisites/
│   └── OCI-Setup.md
├── setup/
│   ├── nim-deployment.yaml
│   └── nim-service.yaml
├── oracle-oke-architecture.png
└── README.md

---

## 🔐 Secrets Setup

Create a Kubernetes secret for NGC API key:

```bash
kubectl create secret generic nim-secret \
  --from-literal=NGC_API_KEY=<YOUR_NGC_API_KEY>
```

Create a Docker registry secret for pulling NIM image:

```bash
kubectl create secret docker-registry registry-secret \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password=<YOUR_NGC_API_KEY>
```

---

## 🚀 Deploy the Model

```bash
kubectl apply -f setup/nim-deployment.yaml
kubectl apply -f setup/nim-service.yaml
```

Watch the pod:
```bash
kubectl get pods -w
```

---

## 🔁 Port Forward for Local Testing

OCI LoadBalancers may take time to assign public IPs or require NSG config. Use port-forwarding for immediate access:

```bash
kubectl port-forward service/nim-llama 8000:8000
```

Then test it:
```bash
curl -X POST http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta/llama3-8b-instruct",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "What is a fixed-rate mortgage?"}
    ],
    "max_tokens": 128,
    "temperature": 0.7
  }'


 Expected Response:
  ```json
  {
    "choices": [
      {
        "message": {
          "role": "assistant",
          "content": "A fixed-rate mortgage is a type of home loan where the interest rate remains the same for the entire term..."
        }
      }
    ]
}

```

---

## 🧼 Cleanup

```bash
kubectl delete -f setup/nim-deployment.yaml
kubectl delete -f setup/nim-service.yaml
kubectl delete secret nim-secret registry-secret
```

---

## 📸 Screenshot (optional)
> Include `kubectl get pods` + successful curl response as visual confirmation in GitHub PR.

---

## ✅ Status
**Working & tested on OCI A100 (OKE)** — powered by NVIDIA NIM 🚀
