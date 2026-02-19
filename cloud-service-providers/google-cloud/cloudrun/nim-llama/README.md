# Deploying NIMs to Google Cloud Run

This guide outlines the steps to deploy a NIM LLM to Google Cloud Run.

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
export NGC_API_KEY=<PASTE_API_KEY_HERE>
export ARTIFACT_REGISTRY_NAME=<DEFINE_ARTIFACT_REGISTRY_NAME_HERE>
export CLOUD_RUN_SERVICE_NAME=<DEFINE_CLOUD_RUN_SERVICE_NAME_HERE>
```

### 2. Log in to NVIDIA NGC Registry (using environment variable)

```shell
echo $NGC_API_KEY | docker login nvcr.io --username '$oauthtoken' --password-stdin
```

### 3. Pull Docker Image from NGC

```shell
docker pull nvcr.io/nim/meta/llama3-8b-instruct:1.0.0
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
docker tag nvcr.io/nim/meta/llama3-8b-instruct:1.0.0 \
  ${REGION}-docker.pkg.dev/${PROJECT_ID}/$ARTIFACT_REGISTRY_NAME/llama3-8b-instruct:1.0.0

docker push ${REGION}-docker.pkg.dev/${PROJECT_ID}/$ARTIFACT_REGISTRY_NAME/llama3-8b-instruct:1.0.0
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
        autoscaling.knative.dev/maxScale: '2'
        run.googleapis.com/cpu-throttling: 'false'
        run.googleapis.com/gpu-zonal-redundancy-disabled: "true"
    spec:
      containers:
      - image: ${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REGISTRY_NAME}/llama3-8b-instruct:1.0.0
        env:
          - name: NGC_API_KEY
            value: ${NGC_API_KEY}
        ports:
          - containerPort: 8000
        resources:
          limits:
            cpu: "8"
            memory: "32Gi"
            nvidia.com/gpu: "1"
        startupProbe:
          initialDelaySeconds: 100
          timeoutSeconds: 240
          periodSeconds: 240
          failureThreshold: 10
          httpGet:
            path: /v1/health/ready
            port: 8000
      nodeSelector:
        run.googleapis.com/accelerator: nvidia-l4
EOF
```

### 9. Deploy to Cloud Run

```shell
gcloud run services replace deployment.yaml \
  --region=${REGION} \
  --project=${PROJECT_ID}
```

### 10. verify deployment was successful

```shell
gcloud run services list --project ${PROJECT_ID} --region ${REGION}
```

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
  "messages": [
    {
      "content": "You are a polite and respectful chatbot helping people plan a vacation.",
      "role": "system"
    },
    {
      "content": "What should I do for a 4 week vacation in Europe?",
      "role": "user"
    }
  ],
  "model": "meta/llama3-8b-instruct",
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
docker rmi nvcr.io/nim/meta/llama3-8b-instruct:1.0.0
docker rmi ${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REGISTRY_NAME}/llama3-8b-instruct:1.0.0

# Logout from NGC registry
docker logout nvcr.io
```
