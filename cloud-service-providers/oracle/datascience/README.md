# Deploy an NVIDIA NIM Microservice on Oracle Data Science Service

This guide provides step-by-step instructions for deploying and managing containerized AI models using NVIDIA NIM on Oracle Cloud Infrastructure (OCI) Data Science Service.

> *For the most up-to-date information, please refer to [NVIDIA NIM Documentation](https://docs.nvidia.com/nim/) and [OCI Data Science](https://docs.oracle.com/en-us/iaas/data-science/).*

## Overview

This guide walks you through deploying an NVIDIA NIM (NVIDIA Inference Microservices) on OCI Data Science using **Nemotron Super 49B**, a custom container image, and capacity reservation. You will create a VCN, a Data Science project, a model artifact, and a model deployment, then run inference against the deployed NIM.

### Key steps

- Create a VCN
- Create a Data Science project and model artifact
- Create a model deployment with capacity reservation (Console or Python)
- Test the deployment with inference requests

## Prerequisites

Before starting, ensure you have:

- **OCI Account** with access to Data Science and GPU capacity
- **NVIDIA NGC Account** for an NGC API Key — [Sign up here](https://ngc.nvidia.com/setup/api-key)
- **GPU shape**: Depends on model — Nemotron Super 49B requires **1x H100** or **2x A100**
- **Capacity Reservation OCID** — Provided to you during the workshop or created in your tenancy
- **Model Artifact** — Download the sample file from the console, then upload it back (see Task 3)
- **Container Image** — Nemotron Super 49B NIM image in OCI Container Registry (e.g. `syd.ocir.io/<your-ocir-namespace>/nemotron-super:latest` or as provided)

**Cloud Shell**: Use OCI Cloud Shell (click the `>_` icon in the top-right of the OCI Console) when you need to run Python scripts; it has OCI CLI pre-configured.

---

## Task 1: Create a VCN

1. Navigate to **Networking** → **Virtual Cloud Networks** → Click **Start VCN Wizard**
2. Fill in:
   - **Name**: Give it a unique name
   - **Compartment**: your compartment
3. Click **Next** → **Create**
4. Wait for VCN status to become **Available**

---

## Task 2: Create a Data Science Project

1. Navigate to **Analytics & AI** → **Data Science** → **Projects**
2. Click **Create Project**
   - **Name**: Give it a unique name
   - **Compartment**: your compartment
3. Click **Create**

---

## Task 3: Create a Model Artifact

1. In your project, click **Models** (left sidebar) → **Create Model**
2. Download the sample model artifact file from the console (if offered), then upload that same file back. Otherwise upload any small ZIP file.
3. Click **Next** through all steps → **Create**
4. Wait for model to become **Active**

---

## Task 4: Create Model Deployment with Capacity Reservation

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

---

## Task 5: Test the Deployment

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

---

## Troubleshooting

| Issue | Action |
|------|--------|
| Deployment fails with "Failed to provision compute resources" | Verify GPU quota in your region; verify capacity reservation OCID is correct |
| Test returns 404 | Wait for deployment to be fully **ACTIVE**; verify model name matches your NIM (e.g. `nvidia/llama-3.3-nemotron-super-49b-v1.5`); check endpoint URL ends with `/predict` |
| Capacity reservation not being used | Verify capacity reservation OCID; ensure shape matches (1x H100 or 2x A100 for Nemotron Super 49B) |
| Container image not found | Use the exact Nemotron Super 49B NIM image path (e.g. from OCIR); ensure the image matches the model you are deploying |

---

## Deployment Checklist

Before testing, ensure:

- [ ] VCN is **Available**
- [ ] Data Science project and model artifact are **Active**
- [ ] Model deployment is **Active** (10–15 min after create)
- [ ] Deployment URL is known (from Model Deployment page)
- [ ] NGC API key is set in environment variables (Console) or in Python script
- [ ] `predict_url` in `test_nim.py` is set to `<your-deployment-url>/predict`

---

## Cleanup

When done:

1. Delete **Model Deployment**
2. Delete **Model**
3. Delete **Data Science Project**
4. Delete **VCN**

---

## Resources

- [NIM on Data Science Workshop](../workshops/NIM%20on%20Data%20Science%20Workshop.md) — hands-on workshop version
- [NVIDIA NIM Documentation](https://docs.nvidia.com/nim/)
- [OCI Data Science Documentation](https://docs.oracle.com/en-us/iaas/data-science/)
- [NVIDIA AI Enterprise](https://www.nvidia.com/en-us/data-center/products/nvidia-ai-enterprise/)
- [NVIDIA Build Platform](https://build.nvidia.com/)
