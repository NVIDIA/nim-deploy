source .env
ngc cloud-function function create \
    --container-image nvcr.io/${NIM_NGC_ORG}/${NIM_CONTAINER_NAME}:${NIM_CONTAINER_TAG} \
    --health-uri /v1/health/ready \
    --inference-url /v1/chat/completions \
    --inference-port 8000 \
    --name ${NIM_CONTAINER_NAME}_${NIM_CONTAINER_TAG}