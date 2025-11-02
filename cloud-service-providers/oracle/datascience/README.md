# NVIDIA NIM Deployment on OCI Data Science (CLI)

This guide provides **step-by-step instructions** for deploying **NVIDIA NIM** models on **Oracle Cloud Infrastructure (OCI) Data Science** using the **CLI**.  

The example below deploys the **LLaMA 3.2 1B Instruct** model (`meta/llama-3.2-1b-instruct`), but the same process applies to any other NIM model available in NVIDIA NGC.

---

## ✅ Supported GPU Shapes

OCI Data Science currently supports the following GPU shapes for NIM deployments:

- **BM.GPU.A10.4**
- **BM.GPU.A100.1**
- **BM.GPU.A100-v2.8**
- **BM.GPU.L40S.4**
- **BM.GPU.H100.8**
- **BM.GPU.H200.8**
- **BM.GPU.B200.8**
- **BM.GPU.GB200.4**
  
Choose a shape based on the NIM model size and inference requirements.

---

## ✅ Tested Environment

- **OCI Data Science**: v1.7  
- **OCI CLI**: v3.42.1  
- **Shape Tested**: BM.GPU.A100-v2.8 
- **NIM Model**: meta/llama-3.2-1b-instruct:latest  

---

## ✅ Prerequisites

- OCI CLI installed and configured (`oci setup config`)  
- OCI Data Science service enabled in your tenancy  
- [NGC API Key](https://ngc.nvidia.com/setup/api-key) (for pulling NIM containers/models)  
- OCI Container Registry (OCIR) access  
- (Optional) OCI Vault for securely storing secrets  
- Basic familiarity with command-line operations

---

## ✅ Required IAM Policies

The following minimum policies are required for the compartment where the NIM deployment will run:

```
Allow group <group-name> to manage data-science-family in compartment <compartment-name>
Allow group <group-name> to use virtual-network-family in compartment <compartment-name>
Allow group <group-name> to manage object-family in compartment <compartment-name>
Allow group <group-name> to manage repos in compartment <compartment-name>
```

If using OCI Vault for secret management:

```
Allow group <group-name> to manage vaults in compartment <compartment-name>
Allow group <group-name> to manage keys in compartment <compartment-name>
```

Replace `<group-name>` and `<compartment-name>` as appropriate.

---

## ✅ 1. Setup Configuration

Create a `config.sh` file:

```bash
#!/bin/bash

# OCI Configuration
export TENANCY_OCID="<your-tenancy-ocid>"
export COMPARTMENT_OCID="<your-compartment-ocid>"
export REGION="<your-region>"
export PROJECT_NAME="nim-llama3"

# OCIR Configuration
export OCIR_NAMESPACE="<your-ocir-namespace>"
export OCIR_REPO="${REGION}.ocir.io/${OCIR_NAMESPACE}/nim"

# NGC Configuration
export NGC_API_KEY="<your-ngc-api-key>"
export MODEL_NAME="meta/llama-3.2-1b-instruct"
```

Load it:

```bash
source ./config.sh
```

---

## ✅ 2. Authenticate with OCI

```bash
oci os ns get
```

---

## ✅ 3. Create OCI Data Science Project

```bash
oci data-science project create \
  --compartment-id $COMPARTMENT_OCID \
  --display-name $PROJECT_NAME
```

Export the Project OCID:

```bash
export PROJECT_OCID="<your-project-ocid>"
```

---

## ✅ 4. Store NGC API Key

**Option 1: OCI Vault (Recommended)**

```bash
oci vault secret create-base64 \
  --compartment-id $COMPARTMENT_OCID \
  --vault-id <vault-ocid> \
  --secret-name "NGC_API_KEY" \
  --secret-content-content "$(echo -n $NGC_API_KEY | base64)"
```

**Option 2: Environment Variable**

Use `$NGC_API_KEY` directly during deployment.

---

## ✅ 5. Authenticate with NGC

```bash
echo $NGC_API_KEY | docker login nvcr.io -u "\$oauthtoken" --password-stdin
```

---

## ✅ 6. Pull NIM Container

```bash
docker pull nvcr.io/nim/${MODEL_NAME}:latest
```

---

## ✅ 7. Create Model Artifact

Create the artifact directory:

```bash
mkdir -p model_artifact
```

Create `score.py`:

```python
import os
import json
import requests

def load_model():
    return None

def predict(data, model=load_model()):
    request_data = json.loads(data)
    nim_endpoint = "http://localhost:9999/v1/chat/completions"
    response = requests.post(nim_endpoint, json=request_data)
    return response.json()
```

Create `runtime.yaml`:

```yaml
MODEL_ARTIFACT_VERSION: '3.0'
MODEL_DEPLOYMENT:
  INFERENCE_CONDA_ENV:
    INFERENCE_ENV_PATH: oci://service-conda-packs@id19sfcrra6z/service_pack/cpu/General Machine Learning for CPU on Python 3.8/1.0/mlcpuv1
    INFERENCE_ENV_SLUG: mlcpuv1
    INFERENCE_ENV_TYPE: data_science
    INFERENCE_PYTHON_VERSION: 3.8
  INFERENCE_SERVER_TYPE: CONTAINER
  CONTAINER_CONFIG:
    IMAGE: nvcr.io/nim/meta/llama-3.2-1b-instruct:latest
    ENV:
      - name: NGC_API_KEY
        value: <your-ngc-api-key>
      - name: MODEL_NAME
        value: meta/llama-3.2-1b-instruct
```

Create `model.json`:

```json
{
  "name": "llama-3.2-1b-nim-model",
  "version": "1.0",
  "framework": "pytorch",
  "input_schema": {
    "type": "object",
    "properties": {
      "messages": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "role": {
              "type": "string",
              "enum": ["system", "user", "assistant"]
            },
            "content": {
              "type": "string"
            }
          },
          "required": ["role", "content"]
        }
      }
    },
    "required": ["messages"]
  },
  "output_schema": {
    "type": "object",
    "properties": {
      "choices": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "message": {
              "type": "object",
              "properties": {
                "role": {
                  "type": "string"
                },
                "content": {
                  "type": "string"
                }
              }
            }
          }
        }
      }
    }
  }
}
```

Create `requirements.txt`:

```
requests>=2.25.0
```

Zip the artifact:

```bash
cd model_artifact && zip -r ../model_artifact.zip .
```

---

## ✅ 8. Create Model in OCI Data Science

```bash
cd .. && source ./config.sh && oci data-science model create \
  --compartment-id $COMPARTMENT_OCID \
  --project-id $PROJECT_OCID \
  --display-name "llama-3.2-1b-nim-model"
```

Export the Model OCID:

```bash
export MODEL_OCID="<your-model-ocid>"
```

---

## ✅ 9. Upload Model Artifact

```bash
source ./config.sh && oci data-science model create-model-artifact \
  --model-id $MODEL_OCID \
  --model-artifact-file model_artifact.zip
```

---

## ✅ 10. Create Model Deployment Configuration

Create `model_deployment_config.json`:

```json
{
  "deploymentType": "SINGLE_MODEL",
  "modelConfigurationDetails": {
    "modelId": "<your-model-ocid>",
    "instanceConfiguration": {
      "instanceShapeName": "BM.GPU.A100-v2.8"
    },
    "bandwidthMbps": 100,
    "scalingPolicy": {
      "policyType": "FIXED_SIZE",
      "instanceCount": 1
    }
  }
}
```

---

## ✅ 11. Create Model Deployment

```bash
source ./config.sh && oci data-science model-deployment create \
  --compartment-id $COMPARTMENT_OCID \
  --project-id $PROJECT_OCID \
  --display-name "llama-3.2-1b-nim-deployment" \
  --model-deployment-configuration-details file://model_deployment_config.json
```

Export:

```bash
export MODEL_DEPLOYMENT_OCID="<your-model-deployment-ocid>"
export MODEL_DEPLOYMENT_URL="<your-model-deployment-url>"
```

---

## ✅ 12. Check Deployment Status

```bash
source ./config.sh && oci data-science model-deployment get --model-deployment-id $MODEL_DEPLOYMENT_OCID
```

Wait until `lifecycle-state` is `ACTIVE` (≈10–15 minutes).

---

## ✅ 13. Test the Deployment

Create `test_model.sh`:

```bash
#!/bin/bash
source ./config.sh

STATUS=$(oci data-science model-deployment get --model-deployment-id $MODEL_DEPLOYMENT_OCID --query "data.\"lifecycle-state\"" --raw-output)

if [ "$STATUS" != "ACTIVE" ]; then
  echo "Model deployment is not active yet. Current status: $STATUS"
  exit 1
fi

curl -X POST "$MODEL_DEPLOYMENT_URL/v1/chat/completions" \
  -H "accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{
  "messages": [
    {
      "role": "system",
      "content": "You are a polite and respectful chatbot helping people plan a vacation."
    },
    {
      "role": "user",
      "content": "What should I do for a 4 day vacation in Spain?"
    }
  ],
  "model": "meta/llama-3.2-1b-instruct",
  "max_tokens": 100,
  "temperature": 0.7,
  "n": 1,
  "stream": false,
  "stop": "\n",
  "frequency_penalty": 0.0
}'
```

Make it executable:

```bash
chmod +x test_model.sh
```

Run:

```bash
./test_model.sh
```

---

## ✅ 14. Cleanup

To remove all resources after testing:

```bash
oci data-science model-deployment delete --model-deployment-id $MODEL_DEPLOYMENT_OCID --force
oci data-science model delete --model-id $MODEL_OCID --force
oci data-science project delete --project-id $PROJECT_OCID --force
```
