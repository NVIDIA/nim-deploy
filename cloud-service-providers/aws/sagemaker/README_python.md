# NIM Shim Layer for AWS SageMaker CLI Script Documentation

This documentation provides a guide on how to use the CLI script to easily add a "shim" layer to an existing NVIDIA Inference Microservice (NIM) image so it can be run on AWS SageMaker.

## Prerequisites

Before using the script, ensure the following:
- Docker is installed and running.
- AWS CLI is installed and configured with appropriate permissions.
  - `apt install -y awscli`
- Docker is logged into AWS ECR.
- Python and required packages are installed (`boto3`, `docker`, `jinja2`).
  - `pip install -r requirements.txt`

## Script Overview

The script performs the following tasks:
1. Validates Docker and AWS credentials.
2. Builds and pushes a shimmed Docker image. 
4. Creates an AWS SageMaker endpoint with the shimmed image.
5. Deletes existing SageMaker resources if needed.
6. Tests the deployed SageMaker endpoint.

## Usage

The script can be executed with various options using CLI arguments or by setting environment variables. Below are the command-line options available.

### Command-Line Options

- `--cleanup` : Delete existing SageMaker resources.
- `--create-shim-endpoint` : Build the shim image and deploy it as an endpoint.
- `--create-shim-image` : Build the shim image locally.
- `--test-endpoint` : Test the deployed endpoint with a sample invocation.
- `--validate-prereq` : Validate prerequisites: Docker and AWS credentials.
- `--src-image-path` : Source image path (default: `nvcr.io/nim/meta/llama3-70b-instruct:latest`).
- `--dst-registry` : Destination registry (default: `your-registry.dkr.ecr.us-west-2.amazonaws.com/nim-shim`).
- `--sg-ep-name` : SageMaker endpoint name.
- `--sg-inst-type` : SageMaker instance type (default: `ml.p4d.24xlarge`).
- `--sg-exec-role-arn` : SageMaker execution role ARN (default: `arn:aws:iam::YOUR-ARN-ROLE:role/service-role/AmazonSageMakerServiceCatalogProductsUseRole`).
- `--sg-container-startup-timeout` : SageMaker container startup timeout (default: `850` seconds).
- `--aws-region` : AWS region (default: `us-west-2`).
- `--test-payload-file` : Test payload template file (default: `sg-invoke-payload.json`).
- `--sg-model-name` : SageMaker model name (default: `default-model-name`).

### Example Usage

#### Validate Prerequisites

To validate Docker and AWS credentials, use the following command:
```sh
python launch.py --validate-prereq
```

#### Create Shim Image Locally

To build the shim image locally, use the following command:
```sh
python launch.py --create-shim-image
```

#### Create Shim Endpoint

To build the shim image and deploy it as an endpoint, use the following command:
```sh
python launch.py --create-shim-endpoint
```

#### Test Endpoint

To test the deployed SageMaker endpoint, use the following command:
```sh
python launch.py --test-endpoint
```

#### Cleanup Existing SageMaker Resources

To delete existing SageMaker resources, use the following command:
```sh
python launch.py --cleanup
```

### Environment Variables

The script supports the following environment variables, or you may set these same values via CLI arguments:

- `SRC_IMAGE_PATH`: Source image path (default: `nvcr.io/nim/meta/llama3-70b-instruct:latest`).
- `DST_REGISTRY`: Destination registry (default: `your-registry.dkr.ecr.us-west-2.amazonaws.com/nim-shim`).
- `SG_INST_TYPE`: SageMaker instance type (default: `ml.p4d.24xlarge`).
- `SG_EXEC_ROLE_ARN`: SageMaker execution role ARN (default: `arn:aws:iam::YOUR-ARN-ROLE:role/service-role/AmazonSageMakerServiceCatalogProductsUseRole`).
- `SG_CONTAINER_STARTUP_TIMEOUT`: SageMaker container startup timeout (default: `850` seconds).
- `AWS_REGION`: AWS region (default: `us-west-2`).

## Conclusion

This script simplifies the process of adding a shim layer to an existing image and deploying it on AWS SageMaker. Use the appropriate command-line options to validate prerequisites, build and push the shim image, create SageMaker endpoints, and test the deployed endpoints.
