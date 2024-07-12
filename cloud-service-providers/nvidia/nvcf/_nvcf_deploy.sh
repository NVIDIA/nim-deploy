# Deploy the Cloud Function onto L40 GPU with min/max instance set to 1/1
ngc cloud-function function deploy create \
    --deployment-specification GFN:L40:gl40_1.br20_2xlarge:1:1 \
    FUNCION_ID:FUNCTION_VERSION
