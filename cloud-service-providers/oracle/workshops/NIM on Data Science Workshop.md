# Deploy an NVIDIA NIM on Oracle Data Science Service Workshop

## Table of Contents

- [Introduction](#introduction)
- [What You Will Learn](#what-you-will-learn)
- [Learn the Components](#learn-the-components)
- [Setup and Requirements](#setup-and-requirements)
- [Task 1. Create a VCN](#task-1-create-a-vcn)
- [Task 2. Create a Data Science Project](#task-2-create-a-data-science-project)
- [Task 3. Create a Model Artifact](#task-3-create-a-model-artifact)
- [Task 4. Create Model Deployment with Capacity Reservation](#task-4-create-model-deployment-with-capacity-reservation)
- [Task 5. Test the Deployment](#task-5-test-the-deployment)
- [Congratulations!](#congratulations)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)
- [Learn More](#learn-more)

## Introduction

This workshop will guide you through deploying an NVIDIA NIM (NVIDIA Inference Microservices) on **Oracle Cloud Infrastructure (OCI) Data Science Service**. You will use a custom container image (e.g., Nemotron Super 49B), capacity reservation, and the Data Science model deployment flow to run inference against your deployed NIM.

OCI Data Science provides a managed environment for building, training, and deploying ML models. This workshop focuses on **deploying** a pre-built NIM container as a model deployment so you can call it via the Data Science predict API.

This workshop is ideal for:

- **Data scientists and ML engineers** who want to serve NVIDIA NIMs on OCI without managing Kubernetes.
- **Teams evaluating OCI Data Science** for model hosting and inference.
- **Users with GPU capacity reservations** who want to deploy NIMs using the Console or Python SDK.

## What You Will Learn

By the end of this workshop, you will have hands-on experience with:

1. **Creating core OCI resources**: VCN, Data Science project, and model artifact.
2. **Creating a model deployment with capacity reservation**: Using either the Console UI or the Python SDK.
3. **Configuring a custom NIM container**: Image, port, and environment variables (e.g., NGC API key, health endpoints).
4. **Testing the deployment**: Sending inference requests to the deployed NIM and verifying responses.

## Learn the Components

### OCI Data Science Service

[OCI Data Science](https://docs.oracle.com/en-us/iaas/data-science/) lets you build, train, and deploy ML models on OCI. For this workshop, you use:

- **Projects**: Organize models and deployments
- **Models**: Model artifacts (for NIM, we use a placeholder artifact; the real serving is via the custom container)
- **Model Deployments**: Run your container with GPU shapes and optional capacity reservation

### NVIDIA NIM (NVIDIA Inference Microservices)

[NVIDIA NIMs](https://developer.nvidia.com/nim) are optimized inference microservices for foundation models. They provide:

- Pre-optimized containers for popular models (e.g., Nemotron Super 49B)
- OpenAI-compatible or custom APIs for completions and health checks

### Capacity Reservation

A capacity reservation guarantees GPU capacity in your tenancy. For this workshop, you use a **Capacity Reservation OCID** when creating the model deployment so the deployment uses reserved capacity. Your tenancy or workshop facilitator provides this OCID.

## Setup and Requirements

### What You Need

To complete this workshop, you need:

- **OCI Account** with access to Data Science and GPU capacity
- **NVIDIA NGC Account** for an NGC API Key — [Sign up here](https://ngc.nvidia.com/setup/api-key)
- **Capacity Reservation OCID** — Provided for the workshop or created in your tenancy
- **Container Image** — Nemotron Super 49B NIM image in OCI Container Registry (e.g., `syd.ocir.io/<your-ocir-namespace>/nemotron-super:latest` or as provided by the workshop)
- **Cloud Shell** — Use OCI Cloud Shell (click the `>_` icon in the OCI Console) when running Python scripts; it has the OCI CLI pre-configured

### GPU Requirements

GPU capacity uses **bare metal (BM) shapes only**; nodes come in **full node** configurations (e.g., 8 GPUs per node). Select a BM shape, such as `BM.GPU.H100.8` or `BM.GPU.A100-v2.8` for Nemotron Super 49B.

### IAM Policy Requirements

Ensure your user/group has the following OCI permissions:

```
Allow group <GROUP_NAME> to manage data-science-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to use virtual-network-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to manage object-family in compartment <COMPARTMENT_NAME>
Allow group <GROUP_NAME> to manage repos in compartment <COMPARTMENT_NAME>
```

## Task 1. Create a VCN

In this task, you'll create a VCN for your Data Science deployment.

1. Navigate to **Networking** → **Virtual Cloud Networks** → Click **Start VCN Wizard**.
2. Fill in:
   - **Name**: Give it a unique name.
   - **Compartment**: Your compartment.
3. Click **Next** → **Create**.
4. Wait for the VCN status to become **Available**.

## Task 2. Create a Data Science Project

In this task, you'll create a Data Science project to hold your model and deployment.

1. Navigate to **Analytics & AI** → **Data Science** → **Projects**.
2. Click **Create Project**.
   - **Name**: Give it a unique name.
   - **Compartment**: Your compartment.
3. Click **Create**.

## Task 3. Create a Model Artifact

In this task, you'll create a model artifact (placeholder) required by the Data Science deployment flow.

1. In your project, click **Models** (left sidebar) → **Create Model**.
2. Download the sample model artifact file from the console (if offered), then upload that same file back. Otherwise, upload any small ZIP file.
3. Click **Next** through all steps → **Create**.
4. Wait for the model to become **Active**.

## Task 4. Create Model Deployment with Capacity Reservation

In this task, you'll create a model deployment that runs your NIM container with GPU and capacity reservation.

> **Note**: Capacity reservation is required for this deployment. The necessary IAM policies are already configured in your tenancy.

### Option A: Deploy Using Console UI (Recommended)

1. In your project, click **Model Deployments** → **Create Model Deployment**.

2. **Basic Configuration**:
   - **Name**: Give it a unique name.
   - **Compartment**: Your compartment.

3. **Select Model**:
   - Click **Select** → Choose the model you created → **Select**.

4. **Compute**:
   - Click **Change Shape**.
   - Select a **bare metal (BM)** shape; only full-node shapes are available (e.g., `BM.GPU.H100.8` or `BM.GPU.A100-v2.8` for Nemotron Super 49B).
   - **Instance count**: 1.
   - **Capacity Reservation ID**: Paste your capacity reservation OCID.

5. **Networking**:
   - Select **Custom networking**.
   - **VCN**: Choose your VCN.
   - **Subnet**: Choose a public subnet.

6. **Container**:
   - Check **Use a custom container image**.
   - Click **Select**.
   - **Image**: Your Nemotron Super 49B NIM image (e.g., `syd.ocir.io/<your-ocir-namespace>/nemotron-super:latest`).
   - **Port**: 8080.

7. **Environment Variables**:
   - Click **Show advanced options** → **Environment Variables**.
   - Add each of the following:

   | Name | Value |
   |------|-------|
   | MODEL_DEPLOY_PREDICT_ENDPOINT | /v1/completions |
   | MODEL_DEPLOY_HEALTH_ENDPOINT | /v1/health/ready |
   | NIM_SERVER_PORT | 8080 |
   | SHM_SIZE | 10g |
   | NCCL_CUMEM_ENABLE | 0 |
   | WEB_CONCURRENCY | 1 |
   | NGC_API_KEY | Your NGC API key from [ngc.nvidia.com](https://ngc.nvidia.com/setup/api-key) |
   | OPENSSL_FORCE_FIPS_MODE | 0 |
   | STORAGE_SIZE_IN_GB | 150 |

8. Click **Create**.
9. Wait 10-15 minutes for the deployment to become **Active**.

### Option B: Deploy Using Python (Alternative)

1. Open **Cloud Shell** and create `deploy_nim_capacity_reservation.py`:

   ```bash
   nano deploy_nim_capacity_reservation.py
   ```

2. Copy and paste the following (adjust region, OCIDs, and image):

   ```python
   import oci

   config = oci.config.from_file(profile_name='DEFAULT')
   config["region"] = "ap-sydney-1"  # Change to your region

   ds_client = oci.data_science.DataScienceClient(config)

   instance_config = oci.data_science.models.InstanceConfiguration(
       instance_shape_name="BM.GPU.A100-v2.8",
       subnet_id="<your-subnet-ocid>"
   )
   instance_config.capacity_reservation_id = "<your-capacity-reservation-ocid>"

   deployment = oci.data_science.models.CreateModelDeploymentDetails(
       display_name="nemotron-super-nim-with-cr",
       compartment_id="<your-compartment-ocid>",
       project_id="<your-project-ocid>",
       model_deployment_configuration_details=oci.data_science.models.SingleModelDeploymentConfigurationDetails(
           deployment_type="SINGLE_MODEL",
           model_configuration_details=oci.data_science.models.ModelConfigurationDetails(
               model_id="<your-model-ocid>",
               instance_configuration=instance_config,
               scaling_policy=oci.data_science.models.FixedSizeScalingPolicy(
                   policy_type="FIXED_SIZE",
                   instance_count=1
               ),
               bandwidth_mbps=10
           ),
           environment_configuration_details=oci.data_science.models.OcirModelDeploymentEnvironmentConfigurationDetails(
               environment_configuration_type="OCIR_CONTAINER",
               image="syd.ocir.io/<your-ocir-namespace>/nemotron-super:latest",
               server_port=8080,
               health_check_port=8080,
               environment_variables={
                   "MODEL_DEPLOY_PREDICT_ENDPOINT": "/v1/completions",
                   "MODEL_DEPLOY_HEALTH_ENDPOINT": "/v1/health/ready",
                   "NGC_API_KEY": "<your-ngc-api-key>",
                   "NIM_SERVER_PORT": "8080",
                   "SHM_SIZE": "10g",
                   "NCCL_CUMEM_ENABLE": "0",
                   "WEB_CONCURRENCY": "1",
                   "OPENSSL_FORCE_FIPS_MODE": "0",
                   "STORAGE_SIZE_IN_GB": "150"
               }
           )
       )
   )

   response = ds_client.create_model_deployment(deployment)
   print(f"Deployment Created: {response.data.id}")
   ```

3. Run:

   ```bash
   python deploy_nim_capacity_reservation.py
   ```

4. Wait 10-15 minutes for the deployment to become **Active**.

## Task 5. Test the Deployment

In this task, you'll send an inference request to your deployed NIM and verify the response.

1. Get your deployment URL from the Model Deployment page.

2. In Cloud Shell, create `test_nim.py`:

   ```bash
   nano test_nim.py
   ```

3. Use the following (set `predict_url` and ensure OCI auth is configured):

   ```python
   import requests
   import oci

   config = oci.config.from_file(profile_name='DEFAULT')
   config["region"] = "ap-sydney-1"
   auth = oci.signer.Signer(
       tenancy=config["tenancy"],
       user=config["user"],
       fingerprint=config["fingerprint"],
       private_key_file_location=config.get("key_file")
   )

   predict_url = "<your-deployment-url>/predict"

   payload = {
       "model": "nvidia/llama-3.3-nemotron-super-49b-v1.5",
       "prompt": "What is NVIDIA NIM?",
       "max_tokens": 100,
       "temperature": 0.7
   }

   response = requests.post(predict_url, json=payload, auth=auth, verify=False, timeout=30)

   if response.status_code == 200:
       result = response.json()
       print("SUCCESS!")
       print(f"Response: {result['choices'][0]['text']}")
   else:
       print(f"Error {response.status_code}: {response.text}")
   ```

4. Run:

   ```bash
   python test_nim.py
   ```

**Expected output:** A successful response with generated text. The model name in the payload must match your NIM (e.g., `nvidia/llama-3.3-nemotron-super-49b-v1.5` for Nemotron Super 49B).

## Congratulations!

You have deployed an NVIDIA NIM on OCI Data Science and run inference against it. You can now:

- Use the same pattern for other NIM images and shapes
- Integrate the deployment URL into your applications
- Scale or update the deployment via the Console or SDK

## Troubleshooting

| Issue | Action |
|-------|--------|
| Deployment fails with "Failed to provision compute resources" | Verify GPU quota and capacity reservation OCID; ensure shape matches reservation. |
| Test returns 404 | Wait for deployment to be **ACTIVE**; verify model name in payload; ensure URL ends with `/predict`. |
| Capacity reservation not used | Verify capacity reservation OCID and that the selected shape matches the reservation. |
| Container image not found | Use the exact NIM image path from OCIR; ensure the image matches the model you are deploying. |

---

## Cleanup

Clean up resources when done.

1. Delete the **Model Deployment**.
2. Delete the **Model**.
3. Delete the **Data Science Project**.
4. Delete the **VCN** (if no longer needed).

## Learn More

- [Deploy NIM on OCI Data Science (Full Guide)](../datascience/README.md) — Detailed guide with all options and verification steps
- [NVIDIA NIMs](https://developer.nvidia.com/nim)
- [NVIDIA NIM Documentation](https://docs.nvidia.com/nim/)
- [OCI Data Science Documentation](https://docs.oracle.com/en-us/iaas/data-science/)
- [NVIDIA AI Enterprise](https://www.nvidia.com/en-us/data-center/products/nvidia-ai-enterprise/)
