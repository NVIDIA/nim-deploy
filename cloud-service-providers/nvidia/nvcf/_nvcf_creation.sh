# Create the Cloud Function based on the Docker image and set environmental variable NGC_API_KEY 
source .env
ngc cloud-function function create \
    --container-image nvcr.io/${NIM_NGC_ORG}/${NIM_CONTAINER_NAME}:${NIM_CONTAINER_TAG} \
    --container-environment-variable NGC_API_KEY:${NGC_API_KEY} \
    --health-uri /v1/health/ready \
    --inference-url ${INFERENCE_URL} \
    --inference-port ${INFERENCE_PORT} \
    --name ${NIM_CONTAINER_NAME}_${NIM_CONTAINER_TAG}