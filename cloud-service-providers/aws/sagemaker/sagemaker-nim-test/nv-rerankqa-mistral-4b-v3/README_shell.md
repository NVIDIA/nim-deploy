# NVIDIA NIM on AWS Sagemaker

## Overview

NVIDIA NIM, a component of NVIDIA AI Enterprise, enhances your applications with the power of state-of-the-art large language models (LLMs), providing unmatched natural language processing and understanding capabilities. Whether you're developing chatbots, content analyzers, or any application that needs to understand and generate human language, NVIDIA NIM for LLMs has you covered.

In this example we show how to build & deploy an AWS Sagemaker-compatible NIM image via AWS CLI and shell commands.

## Contents

- [Preparation](#preparation)
- [Usage](#usage)
  * [Deploying to Sagemaker](#deploying-to-sagemaker)
  * [Deploying locally](#deploying-locally)
- [Testing (Sagemaker)](#testing--sagemaker-)
  * [Invocation](#invocation)
- [Testing (Local)](#testing--local-)
  * [Health](#health)
  * [Invocation](#invocation-1)
    + [Non-streaming](#non-streaming)
    + [Streaming](#streaming)
- [Cleanup](#cleanup)

## Preparation

> 🛈 **[Prefer python? Check here](README_python.md)**

Customize the environment variables below to match your AWS, NGC, etc. configuration(s). If needed, customize the the parameters passed to the `launch.sh` call to ensure proper mapping of frontend/backend ports and source entrypoint. At a minimum you should customize the following:
- `NGC_API_KEY`
- `SG_INST_TYPE`
  - Note that `ml.p4d.24xlarge` or similar variants are required for larger models like llama3-70b. `ml.g5.4xlarge` will work fine for this model
- `SG_EXEC_ROLE_ARN` (Create SageMaker Execution Role or use an existing one)
- Install AWS CLI

```bash
### Set your NGC API Key
export NGC_API_KEY=nvapi-your-api-key

export SRC_IMAGE_PATH=nvcr.io/nim/nvidia/nv-rerankqa-mistral-4b-v3:1.0.2
export SRC_IMAGE_NAME="${SRC_IMAGE_PATH##*/}"
export SRC_IMAGE_NAME="${SRC_IMAGE_NAME%%:*}"
export SRC_IMAGE_NAME="${SRC_IMAGE_NAME//./-}"
export SRC_IMAGE=${SRC_IMAGE_PATH}

# Login to NVCR and pull source image
$ docker login nvcr.io
Username: $oauthtoken
Password: <PASTE_API_KEY_HERE>

docker pull ${SRC_IMAGE_PATH}

# Create ECR repo and login to ECR
export DEFAULT_AWS_REGION=us-east-1
export DST_REGISTRY=$(aws ecr create-repository --repository-name "$SRC_IMAGE_NAME" --query 'repository.repositoryUri' --output text)
aws ecr get-login-password | docker login --username AWS --password-stdin ${DST_REGISTRY}

# Build shimmed image
# sed 's/{{ SRC_IMAGE }}/$SRC_IMAGE/g' Dockerfile > Dockerfile.tmp # come back to fix command skip this
# envsubst < Dockerfile.tmp > Dockerfile.nim # come back to fix command, skip this
docker build -f Dockerfile.nim -t ${DST_REGISTRY}:${SRC_IMAGE_NAME} -t nim-shim-${SRC_IMAGE_NAME}:latest .
docker push ${DST_REGISTRY}:${SRC_IMAGE_NAME}

export SG_EP_NAME="nim-llm-${SRC_IMAGE_NAME}"
export SG_EP_CONTAINER=${DST_REGISTRY}:${SRC_IMAGE_NAME}
export SG_INST_TYPE=ml.g5.4xlarge # -- use larger instance e.g. ml.p4d.24xlarge for large models
export SG_EXEC_ROLE_ARN="arn:aws:iam::YOUR-ARN-ROLE:role/service-role/AmazonSageMakerServiceCatalogProductsUseRole"
export SG_CONTAINER_STARTUP_TIMEOUT=850 #in seconds -- adjust depending on dynamic or S3 model pull; model parameters (70b can take 460s+ to download)
```

## Usage

### Deploying to Sagemaker

Review logs in Cloudwatch. Ensure proper instance types have been set for the correlated model you're running & startup timeout values have been set to sane values, especially for dynamic download of large models (70b+).

```bash
# Generate model JSON
envsubst < templates/sg-model.template > sg-model.json

# Create Model
aws sagemaker create-model \
    --cli-input-json file://sg-model.json

# Create Endpoint Config
aws sagemaker create-endpoint-config \
    --endpoint-config-name $SG_EP_NAME \
    --production-variants "$(envsubst < templates/sg-prod-variant.template)"

# Create Endpoint
aws sagemaker create-endpoint \
    --endpoint-name $SG_EP_NAME \
    --endpoint-config-name $SG_EP_NAME
```

### Deploying locally

Start the container and monitor for:
- Caddy download & launch
- Model weight(s) download
- Service startup(s)


```bash
# Optional (but recommended to expedite future NIM launch times)
mkdir -p /opt/nim/cache

# Start NIM Shim container
docker run -it --rm -v /opt/nim/cache:/opt/nim/.cache -e NGC_API_KEY=$NGC_API_KEY -p 8080:8080 nim-shim:latest
```

## Testing (Sagemaker)

### Invocation
```bash
# Generate sample payload JSON
export SG_MODEL_NAME="nvidia/nv-rerankqa-mistral-4b-v3"
envsubst < templates/sg-test-payload.template > sg-invoke-payload.json

# Create sample invocation
aws sagemaker-runtime invoke-endpoint \
    --endpoint-name $SG_EP_NAME \
    --body file://sg-invoke-payload.json \
    --content-type application/json \
    --cli-binary-format raw-in-base64-out \
    sg-invoke-output.json
```

## Testing (Local)


### Health
Confirm Sagemaker health check will pass:
```bash
curl -X GET 127.0.0.1:8080/ping -vvv
```

### Invocation
```bash
curl -v -X 'POST' \
'http://127.0.0.1:8080/invocations' \
    -H 'accept: application/json' \
    -H 'Content-Type: application/json' \
    -d '{
  "model": "nvidia/nv-rerankqa-mistral-4b-v3",
  "query": {"text": "which way did the traveler go?"},
  "passages": [
    {"text": "two roads diverged in a yellow wood, and sorry i could not travel both and be one traveler, long i stood and looked down one as far as i could to where it bent in the undergrowth;"},
    {"text": "then took the other, as just as fair, and having perhaps the better claim because it was grassy and wanted wear, though as for that the passing there had worn them really about the same,"},
    {"text": "and both that morning equally lay in leaves no step had trodden black. oh, i marked the first for another day! yet knowing how way leads on to way i doubted if i should ever come back."},
    {"text": "i shall be telling this with a sigh somewhere ages and ages hense: two roads diverged in a wood, and i, i took the one less traveled by, and that has made all the difference."}
  ],
  "truncate": "END"
}'
```

## Cleanup

Purge your Sagemaker resources (if desired) between runs:
```bash
# Cleanup Sagemaker
sg_delete_resources() {
    local endpoint_name=$1
    # Delete endpoint
    aws sagemaker delete-endpoint --endpoint-name $endpoint_name || true
    # Wait for the endpoint to be deleted
    aws sagemaker wait endpoint-deleted --endpoint-name $endpoint_name || true
    # Delete endpoint config
    aws sagemaker delete-endpoint-config --endpoint-config-name $endpoint_name || true
    # Delete model
    aws sagemaker delete-model --model-name $endpoint_name || true
}

# Delete existing resources
sg_delete_resources $SG_EP_NAME
```
