# Deploy the Cloud Function onto L40 GPU with min/max instance set to 1/1
export FUNCTION_ID=`ngc cloud-function function list --name-pattern ${NIM_CONTAINER_NAME}_${NIM_CONTAINER_TAG} --format_type json | jq -r '.[0].id'`
export FUNCTION_VERSION=`ngc cloud-function function list --name-pattern ${NIM_CONTAINER_NAME}_${NIM_CONTAINER_TAG} --format_type json | jq -r '.[0].versionId'`
ngc cloud-function function deploy create \
    --deployment-specification GFN:L40:gl40_1.br20_2xlarge:1:1 \
    ${FUNCTION_ID}:${FUNCTION_VERSION}
