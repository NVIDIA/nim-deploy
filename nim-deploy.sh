#!/bin/bash

# Wrapper script for deploying NVIDIA NIM on AWS, GCP, and Azure

NIM_DEPLOY_DIR="./cloud-service-providers"


deploy_aws() {
    local ngc_api_key=$1
    local src_image_path=$2
    local dst_registry=$3
    local sg_inst_type=$4
    local sg_exec_role_arn=$5
    local sg_container_startup_timeout=$6
    local s3_bucket_path=$7

    echo "Deploying NVIDIA NIM on AWS Sagemaker"


    export NGC_API_KEY=$ngc_api_key
    export SRC_IMAGE_PATH=$src_image_path
    export SRC_IMAGE_NAME="${SRC_IMAGE_PATH##*/}"
    export SRC_IMAGE_NAME="${SRC_IMAGE_NAME%%:*}"
    export DST_REGISTRY=$dst_registry
    export SG_EP_NAME="nim-llm-${SRC_IMAGE_NAME}"
    export SG_EP_CONTAINER=${DST_REGISTRY}:${SRC_IMAGE_NAME}
    export SG_INST_TYPE=$sg_inst_type
    export SG_EXEC_ROLE_ARN=$sg_exec_role_arn
    export SG_CONTAINER_STARTUP_TIMEOUT=$sg_container_startup_timeout
    export NIM_REPOSITORY_OVERRIDE=$s3_bucket_path


    docker login nvcr.io
    aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${DST_REGISTRY}

    docker pull ${SRC_IMAGE_PATH}

    cd ./cloud-service-providers/aws/sagemaker

    envsubst < Dockerfile > Dockerfile.nim

    docker build -f Dockerfile.nim -t ${DST_REGISTRY}:${SRC_IMAGE_NAME} -t nim-shim:latest .
    docker push ${DST_REGISTRY}:${SRC_IMAGE_NAME}

    envsubst < templates/sg-model.template > sg-model.json

    aws sagemaker create-model --cli-input-json file://sg-model.json


    aws sagemaker create-endpoint-config \
        --endpoint-config-name $SG_EP_NAME \
        --production-variants "$(envsubst < templates/sg-prod-variant.template)"

    aws sagemaker create-endpoint \
        --endpoint-name $SG_EP_NAME \
        --endpoint-config-name $SG_EP_NAME

    echo "NIM deployed on AWS Sagemaker"
}


deploy_aws_s3_data() {
    local ngc_api_key=$1
    local src_image_path=$2
    local dst_registry=$3
    local sg_inst_type=$4
    local sg_exec_role_arn=$5
    local sg_container_startup_timeout=$6
    local s3_bucket_path=$7

    echo "Deploying NVIDIA NIM on AWS Sagemaker"


    export NGC_API_KEY=$ngc_api_key
    export SRC_IMAGE_PATH=$src_image_path
    export SRC_IMAGE_NAME="${SRC_IMAGE_PATH##*/}"
    export SRC_IMAGE_NAME="${SRC_IMAGE_NAME%%:*}"
    export DST_REGISTRY=$dst_registry
    export SG_EP_NAME="nim-llm-${SRC_IMAGE_NAME}"
    export SG_EP_CONTAINER=${DST_REGISTRY}:${SRC_IMAGE_NAME}
    export SG_INST_TYPE=$sg_inst_type
    export SG_EXEC_ROLE_ARN=$sg_exec_role_arn
    export SG_CONTAINER_STARTUP_TIMEOUT=$sg_container_startup_timeout
    export NIM_REPOSITORY_OVERRIDE=$s3_bucket_path


    docker login nvcr.io
    aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin ${DST_REGISTRY}

    # Model preparation for S3
    echo "Processing model artifacts..."
    
    # Create temporary workspace
    TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TEMP_DIR"' EXIT

    # Extract model manifest
    echo "Extracting model manifest from container..."
    docker pull "$SRC_IMAGE_PATH"
    CONTAINER_ID=$(docker create "$SRC_IMAGE_PATH")
    docker cp "$CONTAINER_ID:/opt/nim/etc/default/model_manifest.yaml" "$TEMP_DIR/"
    docker rm "$CONTAINER_ID" >/dev/null

    # Process manifest files
    echo "Uploading model files to S3..."
    python3 <<EOF
import yaml
import os
import subprocess
from urllib.parse import unquote

with open('$TEMP_DIR/model_manifest.yaml') as f:
    manifest = yaml.safe_load(f)

for file_meta in manifest['profiles'][0]['workspace']['files'].values():
    ngc_uri = file_meta['uri']
    file_query = ngc_uri.split('?file=')[1]
    decoded_path = unquote(file_query)
    print(decoded_path)
    
    # Create container path
    container_path = f"/opt/nim/{unquote(ngc_uri.split('://')[1].split('?')[0])}"
    
    # Create local temp path
    local_path = os.path.join('$TEMP_DIR', os.path.basename(decoded_path))
    
    # Create S3 destination
    s3_path = f"{os.environ['NIM_REPOSITORY_OVERRIDE']}/{decoded_path}"
    
    # Extract from container
    subprocess.run([
        'docker', 'run', '--rm',
        '-v', f'{local_path}:/output',
        os.environ['SRC_IMAGE_PATH'],
        'cp', container_path, '/output'
    ], check=True)
    
    # Upload to S3
    subprocess.run([
        'aws', 's3', 'cp',
        local_path,
        s3_path
    ], check=True)
EOF

    cd ./cloud-service-providers/aws/sagemaker

    envsubst < Dockerfile > Dockerfile.nim

    docker build -f Dockerfile.nim -t ${DST_REGISTRY}:${SRC_IMAGE_NAME} -t nim-shim:latest .
    docker push ${DST_REGISTRY}:${SRC_IMAGE_NAME}

    envsubst < templates/sg-model.template > sg-model.json

    aws sagemaker create-model --cli-input-json file://sg-model.json


    aws sagemaker create-endpoint-config \
        --endpoint-config-name $SG_EP_NAME \
        --production-variants "$(envsubst < templates/sg-prod-variant.template)"

    aws sagemaker create-endpoint \
        --endpoint-name $SG_EP_NAME \
        --endpoint-config-name $SG_EP_NAME

    echo "NIM deployed on AWS Sagemaker from S3"
}


deploy_gcp() {
    # TODO
    echo "NIM not deployed on GCP GKE"
}


deploy_azure() {
    # TODO 
    echo "NIM not deployed on Azure AKS"
}


main() {
    if [ $# -lt 2 ]; then
        echo "Usage: $0 <cloud_provider> [provider-specific arguments]"
        echo "AWS: $0 aws <ngc_api_key> <src_image_path> <dst_registry> <sg_inst_type> <sg_exec_role_arn> <sg_container_startup_timeout>"
        echo "GCP: $0 gcp <project_id> <region> <zone> <machine_type> <cluster_name>"
        echo "Azure: $0 azure <resource_group> <cluster_name> <location> <vm_size>"
        exit 1
    fi

    cloud_provider=$1
    shift

    case $cloud_provider in
        aws)
            if [ $# -ne 7 ]; then
                echo "AWS usage: $0 aws <ngc_api_key> <src_image_path> <dst_registry> <sg_inst_type> <sg_exec_role_arn> <sg_container_startup_timeout>"
                exit 1
            fi
            deploy_aws_s3_data "$@"
            ;;
        gcp)
            if [ $# -ne 5 ]; then
                echo "GCP usage: $0 gcp <project_id> <region> <zone> <machine_type> <cluster_name>"
                exit 1
            fi
            deploy_gcp "$@"
            ;;
        azure)
            if [ $# -ne 4 ]; then
                echo "Azure usage: $0 azure <resource_group> <cluster_name> <location> <vm_size>"
                exit 1
            fi
            deploy_azure "$@"
            ;;
        *)
            echo "Unsupported cloud provider. Choose aws, gcp, or azure."
            exit 1
            ;;
    esac
}

# Run the main function
main "$@"
