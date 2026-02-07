# Deploy an NVIDIA NIM Microservice on Oracle Data Science Service Workshop

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

In this workshop, you will learn how to deploy and manage containerized AI models using NVIDIA NIM on Oracle Data Science Service. This workshop is designed for developers who are looking to simplify AI inference deployment, optimize performance on NVIDIA GPUs, and move faster with an open and integrated AI platform.

This workshop is ideal for developers and data scientists interested in:

- **Simplifying AI inference deployment**: Learn how to leverage pre-built NIM for faster and easier deployment of AI models into production on OCI Data Science.
- **Optimizing performance on NVIDIA GPUs**: Gain hands-on experience with deploying NIMs that leverage NVIDIA TensorRT for optimized inference on GPUs, using Python and open source tools.
- **Moving faster**: Train, tune and deploy ML models in an open and integrated AI platform, on a single surface across all data and AI workloads.

## What You Will Learn

By the end of this workshop, you will have hands-on experience with:

1. **Creating an NVIDIA API Key**
2. **Creating an OCI Data Science Project and a Model Artifact**
3. **Pulling and Deploying an NVIDIA NIM**
4. **Deploying an NVIDIA NIM on an OCI Data Science endpoint**
5. **Making inference to get customized responses**

## Learn the Components

### GPUs in Oracle Data Science Service

GPUs let you accelerate specific workloads running on your nodes such as machine learning and data processing. OCI Data Science provides a range of machine type options. GPU requirements depend on the model; **Nemotron Super 49B** requires **1x H100** or **2x A100**.

### NVIDIA NIM

[NVIDIA NIM](https://www.nvidia.com/en-us/ai/) are a set of easy-to-use inference microservices for accelerating the deployment of foundation models on any cloud or data center and helping to keep your data secure. This workshop uses **Nemotron Super 49B**, the same class of model used in the RAG and AIQ blueprints on OKE.

### NVIDIA AI Enterprise

[NVIDIA AI Enterprise](https://www.nvidia.com/en-us/data-center/products/nvidia-ai-enterprise/) is an end-to-end, cloud-native software platform that accelerates data science pipelines and streamlines development and deployment of production-grade co-pilots and other generative AI applications. Available through OCI Marketplace.

### Cloud Shell Access

Throughout this workshop, when you need to run Python scripts, use OCI Cloud Shell:

1. Click the **Cloud Shell** icon (`>_`) in the top-right corner of the OCI Console
2. This gives you a browser-based terminal with OCI CLI pre-configured

## Setup and Requirements

### What You Need

To complete this workshop, you need:

- **OCI Account** with access to Data Science and GPU capacity
- **NVIDIA NGC Account** for an NGC API Key — [Sign up here](https://ngc.nvidia.com/setup/api-key)
- **GPU shape**: Depends on model — Nemotron Super 49B requires **1x H100** or **2x A100**
- **Capacity Reservation OCID** — Provided to you during the workshop or created in your tenancy
- **Model Artifact** — Download the sample file from the console, then upload it back (see Task 3)
- **Container Image** — Nemotron Super 49B NIM image in OCI Container Registry (e.g. `syd.ocir.io/<your-ocir-namespace>/nemotron-super:latest` or as provided)

## Task 1. Create a VCN

1. Navigate to **Networking** → **Virtual Cloud Networks** → Click **Start VCN Wizard**
2. Fill in:
   - **Name**: Give it a unique name
   - **Compartment**: your compartment
3. Click **Next** → **Create**
4. Wait for VCN status to become **Available**

## Task 2. Create a Data Science Project

1. Navigate to **Analytics & AI** → **Data Science** → **Projects**
2. Click **Create Project**
   - **Name**: Give it a unique name
   - **Compartment**: your compartment
3. Click **Create**

## Task 3. Create a Model Artifact

1. In your project, click **Models** (left sidebar) → **Create Model**
2. Download the sample model artifact file from the console (if offered), then upload that same file back. Otherwise upload any small ZIP file.
3. Click **Next** through all steps → **Create**
4. Wait for model to become **Active**

## Task 4. Create Model Deployment with Capacity Reservation

> **Note**: Capacity reservation is required for this deployment. The necessary IAM policies are already configured in your tenancy.

### Option A: Deploy Using Console UI (Recommended)

1. In your project, click **Model Deployments** → **Create Model Deployment**

2. **Basic Configuration**:
   - **Name**: Give it a unique name
   - **Compartment**: your compartment

3. **Select Model**:
   - Click **Select** → Choose the model you created → **Select**

4. **Compute**:
   - Click **Change Shape**
   - Select a shape with **1x H100** or **2x A100** for Nemotron Super 49B (e.g. VM.GPU.H100.1 or VM.GPU.A100.2)
   - **Instance count**: 1
   - **Capacity Reservation ID**: Paste your capacity reservation OCID

5. **Networking**:
   - Select **Custom networking**
   - **VCN**: Choose your VCN
   - **Subnet**: Choose public subnet

6. **Container**:
   - Check **Use a custom container image**
   - Click **Select**
   - **Image**: Your Nemotron Super 49B NIM image (e.g. `syd.ocir.io/<your-ocir-namespace>/nemotron-super:latest`)
   - **Port**: 8080

7. **Environment Variables**:
   - Click **Show advanced options** → **Environment Variables**
   - Click **+ Another environment variable** for each of the following:

   | Name | Value |
   |------|-------|
   | MODEL_DEPLOY_PREDICT_ENDPOINT | /v1/completions |
   | MODEL_DEPLOY_HEALTH_ENDPOINT | /v1/health/ready |
   | NIM_SERVER_PORT | 8080 |
   | SHM_SIZE | 10g |
   | NCCL_CUMEM_ENABLE | 0 |
   | WEB_CONCURRENCY | 1 |
   | NGC_API_KEY | `your-ngc-api-key` (create one at [ngc.nvidia.com](https://ngc.nvidia.com/setup/api-key)) |
   | OPENSSL_FORCE_FIPS_MODE | 0 |
   | STORAGE_SIZE_IN_GB | 150 |

8. Click **Create**
9. Wait 10-15 minutes for deployment to become **Active**

### Option B: Deploy Using Python (Alternative)

If you prefer to use Python instead of the console:

1. Open Cloud Shell and create `deploy_nim_capacity_reservation.py`:

   ```bash
   nano deploy_nim_capacity_reservation.py
   ```

2. Copy and paste the following code:

   ```python
   import oci

   config = oci.config.from_file(profile_name='DEFAULT')
   config["region"] = "ap-sydney-1"  # Change to your region

   ds_client = oci.data_science.DataScienceClient(config)

   # Create instance configuration with capacity reservation (for Nemotron Super 49B use 1x H100 or 2x A100)
   instance_config = oci.data_science.models.InstanceConfiguration(
       instance_shape_name="VM.GPU.A100.2",  # or VM.GPU.H100.1 / BM.GPU.H100.8 depending on your reservation
       subnet_id="<your-subnet-ocid>"
   )
   instance_config.capacity_reservation_id = "<your-capacity-reservation-ocid>"

   # Create deployment
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
               image_digest="<your-image-digest>",  # Optional: use digest from OCIR for Nemotron Super image
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
   print(f"✅ Deployment Created: {response.data.id}")
   print(f"Status: {response.data.lifecycle_state}")
   ```

   Press **Ctrl+O** to save, **Enter** to confirm, then **Ctrl+X** to exit nano.

3. Run it:

   ```bash
   python deploy_nim_capacity_reservation.py
   ```

4. Wait 10-15 minutes for deployment to become **Active**

### Verify Capacity Reservation (Optional)

1. In Cloud Shell, create `verify_cr.py`:

   ```bash
   nano verify_cr.py
   ```

2. Copy and paste the following code:

   ```python
   import oci

   config = oci.config.from_file(profile_name='DEFAULT')
   config["region"] = "ap-sydney-1"

   compute_client = oci.core.ComputeClient(config)
   cap_res = compute_client.get_compute_capacity_reservation("<your-capacity-reservation-ocid>")

   reservation_config = cap_res.data.instance_reservation_configs[0]
   print(f"Reserved: {reservation_config.reserved_count}")
   print(f"Used: {reservation_config.used_count}")
   print(f"✅ Capacity reservation is {'ACTIVE' if reservation_config.used_count > 0 else 'NOT USED'}")
   ```

   Press **Ctrl+O** to save, **Enter** to confirm, then **Ctrl+X** to exit nano.

3. Run it:

   ```bash
   python verify_cr.py
   ```

## Task 5. Test the Deployment

1. Get your deployment URL from the Model Deployment page

2. In Cloud Shell, create `test_nim.py`:

   ```bash
   nano test_nim.py
   ```

3. Copy and paste the following code:

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
       "model": "nvidia/llama-3.3-nemotron-super-49b-v1.5",  # Nemotron Super 49B — must match your NIM model
       "prompt": "What is NVIDIA NIM?",
       "max_tokens": 100,
       "temperature": 0.7
   }

   response = requests.post(predict_url, json=payload, auth=auth, verify=False, timeout=30)

   if response.status_code == 200:
       result = response.json()
       print("✅ SUCCESS!")
       print(f"Response: {result['choices'][0]['text']}")
       print(f"Tokens: {result['usage']['total_tokens']}")
   else:
       print(f"❌ Error {response.status_code}: {response.text}")
   ```

   Press **Ctrl+O** to save, **Enter** to confirm, then **Ctrl+X** to exit nano.

4. Run it:

   ```bash
   python test_nim.py
   ```

**Expected output:**

```
✅ SUCCESS!
Response: <model response text>
Tokens: <number>
```

> **Important**: Model name must match your NIM deployment (e.g. `nvidia/llama-3.3-nemotron-super-49b-v1.5` for Nemotron Super 49B).

## Congratulations!

You've successfully:

- Deployed NVIDIA NIM on OCI Data Science with capacity reservation
- Made successful inference requests
- Verified your capacity reservation usage

**Next steps:**

- Try different prompts and parameters
- Deploy larger models (70B, 405B)
- Integrate into your applications using OCI SDK

## Troubleshooting

### Deployment fails with "Failed to provision compute resources"

- Verify GPU quota is available in your region
- For capacity reservations: Verify capacity reservation OCID is correct

### Test returns 404

- Wait for deployment to be fully **ACTIVE**
- Verify model name matches your NIM (e.g. `nvidia/llama-3.3-nemotron-super-49b-v1.5` for Nemotron Super 49B)
- Check endpoint URL ends with `/predict`

### Capacity reservation not being used

- Verify capacity reservation OCID is correct
- Check that the shape matches the capacity reservation shape (must be 1x H100 or 2x A100 for Nemotron Super 49B)

### Container image not found

- Use the exact Nemotron Super 49B NIM image path (e.g. from OCIR)
- Ensure the container image matches the model you are deploying

## Cleanup

When done:

1. Delete **Model Deployment**
2. Delete **Model**
3. Delete **Data Science Project**
4. Delete **VCN**

## Learn More

- [NIM on Data Science](../datascience/README.md)
- [NVIDIA NIM Documentation](https://docs.nvidia.com/nim/)
- [OCI Data Science Documentation](https://docs.oracle.com/en-us/iaas/data-science/)
- [NVIDIA AI Enterprise](https://www.nvidia.com/en-us/data-center/products/nvidia-ai-enterprise/)
- [NVIDIA Build Platform](https://build.nvidia.com/)
