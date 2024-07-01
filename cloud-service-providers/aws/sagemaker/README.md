# NIM (NVIDIA Inference Microservice) Shim

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
- `DST_REGISTRY`
- `SG_INST_TYPE`
  - Note that `ml.p4d.24xlarge` or similar variants are required for llama3-70b. `ml.g5.4xlarge` will work fine for `llama3-8b`
- `SG_EXEC_ROLE_ARN`

```bash
git clone https://github.com/liveaverage/nim-shim && cd nim-shim

### Set your NGC API Key
export NGC_API_KEY=nvapi-your-api-key

export SRC_IMAGE_PATH=nvcr.io/nim/meta/llama3-70b-instruct:latest
export SRC_IMAGE_NAME="${SRC_IMAGE_PATH##*/}"
export SRC_IMAGE_NAME="${SRC_IMAGE_NAME%%:*}"
export DST_REGISTRY=your-registry.dkr.ecr.us-west-2.amazonaws.com/nim-shim

docker login nvcr.io
docker login ${DST_REGISTRY}
docker pull ${SRC_IMAGE}

# Build shimmed image
sed 's/{{ SRC_IMAGE }}/$SRC_IMAGE/g' Dockerfile > Dockerfile.tmp
envsubst < Dockerfile.tmp > Dockerfile.nim
docker build -f Dockerfile.nim -t ${DST_REGISTRY}:${SRC_IMAGE_NAME} -t nim-shim:latest .
docker push ${DST_REGISTRY}:${SRC_IMAGE_NAME}

export SG_EP_NAME="nim-llm-${SRC_IMAGE_NAME}"
export SG_EP_CONTAINER=${DST_REGISTRY}:${SRC_IMAGE_NAME}
export SG_INST_TYPE=ml.p4d.24xlarge # ml.g5.4xlarge -- adequate for llama3-8b
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

#### Non-streaming
```bash
curl -X 'POST' \
'http://127.0.0.1:8080/invocations' \
    -H 'accept: application/json' \
    -H 'Content-Type: application/json' \
    -d '{
"model": "meta/llama3-8b-instruct",
"messages": [
{
"role":"user",
"content":"Hello! How are you?"
},
{
"role":"assistant",
"content":"Hi! I am quite well, how can I help you today?"
},
{
"role":"user",
"content":"Can you write me a song?"
}
],
"max_tokens": 32
}'
```

#### Streaming
```bash
curl -X 'POST' \
'http://127.0.0.1:8080/invocations' \
    -H 'accept: application/json' \
    -H 'Content-Type: application/json' \
	-H 'Content-Type: text/event-stream' \
    -d '{
"model": "meta/llama3-8b-instruct",
"messages": [
{
"role":"user",
"content":"Hello! How are you?"
},
{
"role":"assistant",
"content":"Hi! I am quite well, how can I help you today?"
},
{
"role":"user",
"content":"Can you write me a song featuring 90s grunge rock vibes?"
}
],
"max_tokens": 320,
"stream": true
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
