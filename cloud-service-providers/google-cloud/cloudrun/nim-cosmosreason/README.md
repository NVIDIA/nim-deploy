# Deploying NIMs to Google Cloud Run using RTX PRO 6000

This guide outlines the steps to deploy a NIM LLM to Google Cloud Run, using Cosmos Reason 2 8B as an example.

---

## Prerequisites

- [NGC API KEY](https://build.nvidia.com/)
- [gcloud CLI](https://cloud.google.com/sdk/docs/install)
- Docker CLI
- Permissions (ask your administrator to grant you):
  - Cloud Run Developer (`roles/run.developer`)
  - Service Account User (`roles/iam.serviceAccountUser`)
  - Artifact Registry Reader (`roles/artifactregistry.reader`)

---

## Deployment Steps

### 1. Set Environment Variables

```shell
export PROJECT_ID=<PASTE_PROJECT_ID_HERE>
export REGION=<PASTE_REGION_HERE> # e.g. us-central1
export NGC_API_KEY='<PASTE_API_KEY_HERE>'
export ARTIFACT_REGISTRY_NAME=<DEFINE_ARTIFACT_REGISTRY_NAME_HERE>
export CLOUD_RUN_SERVICE_NAME=<DEFINE_CLOUD_RUN_SERVICE_NAME_HERE>
```

### 2. Log in to NVIDIA NGC Registry (using environment variable)

```shell
echo $NGC_API_KEY | docker login nvcr.io --username '$oauthtoken' --password-stdin
```

### 3. Pull Docker Image from NGC

```shell
docker pull nvcr.io/nim/nvidia/cosmos-reason2-8b:latest
```

### 4. Authenticate to Google Cloud

```shell
gcloud auth login
```

### 5. Create Artifact Registry Repository

```shell
gcloud artifacts repositories create $ARTIFACT_REGISTRY_NAME \
    --repository-format=docker \
    --location=$REGION \
    --project=$PROJECT_ID
```

### 6. Log in to Artifact Registry

```shell
gcloud auth configure-docker ${REGION}-docker.pkg.dev
```

### 7. Tag and Push Image to Artifact Registry

```shell
docker tag nvcr.io/nim/nvidia/cosmos-reason2-8b:latest \
  ${REGION}-docker.pkg.dev/${PROJECT_ID}/$ARTIFACT_REGISTRY_NAME/cosmos-reason2-8b:latest

docker push ${REGION}-docker.pkg.dev/${PROJECT_ID}/$ARTIFACT_REGISTRY_NAME/cosmos-reason2-8b:latest
```

### 8. Create `deployment.yaml` with Environment Variables

```shell
cat << EOF > deployment.yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: ${CLOUD_RUN_SERVICE_NAME}
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/minScale: "1"
        autoscaling.knative.dev/maxScale: '2'
        run.googleapis.com/cpu-throttling: 'false'
        run.googleapis.com/gpu-zonal-redundancy-disabled: "true"
        run.googleapis.com/startup-cpu-boost: "true"
    spec:
      containers:
      - image: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REGISTRY_NAME}/cosmos-reason2-8b:latest
        env:
          - name: NGC_API_KEY
            value: ${NGC_API_KEY}
        ports:
          - containerPort: 8000
        resources:
          limits:
            cpu: "20"
            memory: "80Gi"
            nvidia.com/gpu: "1"
        startupProbe:
          initialDelaySeconds: 200
          timeoutSeconds: 30
          periodSeconds: 30
          failureThreshold: 50
          httpGet:
            path: /v1/health/ready
            port: 8000
      nodeSelector:
        run.googleapis.com/accelerator: nvidia-rtx-pro-6000
EOF
```

### 9. Deploy to Cloud Run

```shell
gcloud beta run services replace deployment.yaml   --region=${REGION}   --project=${PROJECT_ID}
```

### 10. verify deployment was successful

```shell
gcloud beta run services list --project ${PROJECT_ID} --region ${REGION}
```
You can confirm the GPU used in Cloud Run by inspecting the logs :
```telemetry_handler.py:123] RTX GPU detected: NVIDIA RTX PRO 6000 Blackwell Server Edition```

### 11. Test Deployment

```shell
# Get service URL
export TESTURL=$(gcloud run services list --project ${PROJECT_ID} --region ${REGION} --format="value(status.url)" --filter="metadata.name=${CLOUD_RUN_SERVICE_NAME}")/v1/chat/completions

# Get authentication token
export TOKEN=$(gcloud auth print-identity-token)

# Send test request
curl -X POST ${TESTURL} \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
    -d '{
        "model": "nvidia/cosmos-reason2-8b",
        "messages": [
            {
                "role": "system",
                "content": "You are a helpful assistant."
            },
            {
                "role": "user",
                "content": [
                    {
                        "type": "image_url",
                        "image_url":
                            {
                                "url": "https://assets.ngc.nvidia.com/products/api-catalog/phi-3-5-vision/example1b.jpg"
                            }
                    },
                    {
                        "type": "text",
                        "text": "What is in this image?"
                    }
                ]
            }
        ],
        "max_tokens": 256,
        "stream": false
    }'
```

You may also try : 

```shell
curl -X POST ${TESTURL} \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $TOKEN" \
    -d '{
        "model": "nvidia/cosmos-reason2-8b",
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": "What is in this video?"
                    },
                    {
                        "type": "video_url",
                        "video_url":
                            {
                                "url": "https://assets.ngc.nvidia.com/products/api-catalog/cosmos-reason1-7b/av_construction_stop_timestamped.mp4"
                            }
                    }
                ]
            }
        ],
        "max_tokens": 256
    }'
```

### 12. Cleanup

```shell
# Delete Cloud Run service
gcloud run services delete ${CLOUD_RUN_SERVICE_NAME} --region=${REGION} --project=${PROJECT_ID}

# Delete Artifact Registry repository
gcloud artifacts repositories delete ${ARTIFACT_REGISTRY_NAME} \
    --location=${REGION} \
    --project=${PROJECT_ID}

# Remove local Docker images
docker rmi nvcr.io/nim/nvidia/nemotron-3-nano:latest
docker rmi ${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REGISTRY_NAME}/nemotron-3-nano:latest

# Logout from NGC registry
docker logout nvcr.io
```
