import os
import sys
import json
import argparse
import boto3
import subprocess
import logging
import time
from jinja2 import Environment, FileSystemLoader
from botocore.exceptions import ClientError
from docker import APIClient, errors

# Default values for environment variables
DEFAULT_SRC_IMAGE_PATH = 'nvcr.io/nim/meta/llama3-70b-instruct:latest'
DEFAULT_DST_REGISTRY = 'your-registry.dkr.ecr.us-west-2.amazonaws.com/nim-shim'
DEFAULT_SG_INST_TYPE = 'ml.p4d.24xlarge'
DEFAULT_SG_EXEC_ROLE_ARN = 'arn:aws:iam::YOUR-ARN-ROLE:role/service-role/AmazonSageMakerServiceCatalogProductsUseRole'
DEFAULT_SG_CONTAINER_STARTUP_TIMEOUT = 850
DEFAULT_AWS_REGION = 'us-west-2'  # Default AWS region

# Configure logger
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Initialize clients with region
def init_boto3_client(service_name):
    return boto3.client(
        service_name,
        region_name=AWS_REGION
    )

client = APIClient(base_url='unix://var/run/docker.sock')
sagemaker_client = None
sagemaker_runtime_client = None

# Docker operations
def docker_login_ecr(region, registry):
    login_command = f"aws ecr get-login-password --region {region} | docker login --username AWS --password-stdin {registry}"
    subprocess.run(login_command, shell=True, check=True)

def docker_pull(image):
    for line in client.pull(image, stream=True, decode=True):
        logger.info(line.get('status', ''))

def docker_build_and_push(dockerfile, tags):
    # Ensure necessary files exist in the current working directory
    required_files = ['launch.sh', 'caddy-config.json']
    missing_files = [f for f in required_files if not os.path.exists(f)]
    if missing_files:
        logger.error(f"Missing required files for Docker build: {missing_files}")
        sys.exit(1)
    
    logger.info("All required files are present for Docker build.")

    # Build the Docker image
    logger.info("Building Docker image...")
    build_start_time = time.time()
    try:
        build_logs = client.build(path='.', dockerfile=dockerfile, tag=tags[0], rm=True, decode=True)
        image_built = False
        for log in build_logs:
            if 'stream' in log:
                logger.info(log['stream'].strip())
            if 'aux' in log and 'ID' in log['aux']:
                image_built = True
            if 'errorDetail' in log:
                logger.error(f"ErrorDetail: {log['errorDetail']}")
                sys.exit(1)
        build_duration = time.time() - build_start_time
        if not image_built:
            logger.error("Failed to build Docker image.")
            sys.exit(1)
        logger.info(f"Building Docker image took {build_duration:.2f} seconds.")
    except errors.BuildError as e:
        logger.error(f"BuildError: {e}")
        sys.exit(1)
    except errors.APIError as e:
        logger.error(f"APIError: {e}")
        sys.exit(1)

    # Tag the Docker image with additional tags
    for tag in tags[1:]:
        try:
            client.tag(tags[0], tag)
        except errors.APIError as e:
            logger.error(f"Failed to tag image: {e}")
            sys.exit(1)

    # Push the Docker image to the registry
    logger.info("Pushing Docker image to registry...")
    push_start_time = time.time()
    try:
        for tag in tags:
            push_logs = client.push(tag, stream=True, decode=True)
            for log in push_logs:
                status = log.get('status', '')
                if 'Waiting' not in status and 'Preparing' not in status and 'Layer already exists' not in status:
                    logger.info(status)
        push_duration = time.time() - push_start_time
        logger.info(f"Pushing Docker image took {push_duration:.2f} seconds.")
    except errors.APIError as e:
        logger.error(f"Failed to push image: {e}")
        sys.exit(1)

def validate_prereq():
    start_time = time.time()
    try:
        # Validate Docker source registry login
        docker_login_ecr(AWS_REGION, DST_REGISTRY)
        logger.info("Docker credentials are valid.")
    except Exception as e:
        logger.error(f"Error validating Docker credentials: {e}")
        sys.exit(1)

    try:
        # Validate AWS credentials
        sts_client = boto3.client('sts', region_name=AWS_REGION)
        sts_client.get_caller_identity()
        logger.info("AWS credentials are valid.")
    except ClientError as e:
        logger.error(f"Error validating AWS credentials: {e}")
        sys.exit(1)
    duration = time.time() - start_time
    logger.info(f"Validation of prerequisites took {duration:.2f} seconds.")

def delete_sagemaker_resources(endpoint_name):
    start_time = time.time()
    def delete_resource(delete_func, resource_type, resource_name):
        try:
            delete_func()
            logger.info(f"Deleted {resource_type}: {resource_name}")
        except ClientError as e:
            if e.response['Error']['Code'] == 'ValidationException' and 'Could not find' in e.response['Error']['Message']:
                logger.info(f"{resource_type} {resource_name} does not exist.")
            else:
                logger.error(f"Error deleting {resource_type} {resource_name}: {e}")

    delete_resource(
        lambda: sagemaker_client.delete_endpoint(EndpointName=endpoint_name),
        "endpoint", endpoint_name
    )

    delete_resource(
        lambda: sagemaker_client.delete_endpoint_config(EndpointConfigName=endpoint_name),
        "endpoint config", endpoint_name
    )

    delete_resource(
        lambda: sagemaker_client.delete_model(ModelName=endpoint_name),
        "model", endpoint_name
    )
    duration = time.time() - start_time
    logger.info(f"Deleting SageMaker resources took {duration:.2f} seconds.")

def create_shim_image():
    start_time = time.time()
    # Docker login and pull
    docker_login_ecr(AWS_REGION, DST_REGISTRY)
    docker_pull(SRC_IMAGE_PATH)

    # Load Dockerfile template and replace placeholder
    env = Environment(loader=FileSystemLoader('.'))
    template = env.get_template('Dockerfile')  # Ensure your template is named Dockerfile.j2
    dockerfile_content = template.render(SRC_IMAGE=SRC_IMAGE_PATH)

    with open('Dockerfile.nim', 'w') as f:
        f.write(dockerfile_content)

    # Ensure necessary files exist in the current working directory
    required_files = ['launch.sh', 'caddy-config.json']
    missing_files = [f for f in required_files if not os.path.exists(f)]
    if missing_files:
        logger.error(f"Missing required files for Docker build: {missing_files}")
        sys.exit(1)
    
    logger.info("All required files are present for Docker build.")
    logger.info("Dockerfile.nim content:")
    with open('Dockerfile.nim', 'r') as f:
        logger.info(f.read())

    # Build the Docker image
    logger.info("Building Docker image...")
    build_start_time = time.time()
    try:
        build_logs = client.build(path='.', dockerfile='Dockerfile.nim', tag='nim-shim:latest', rm=True, decode=True)
        image_built = False
        for log in build_logs:
            if 'stream' in log:
                logger.info(log['stream'].strip())
            if 'aux' in log and 'ID' in log['aux']:
                image_built = True
            if 'errorDetail' in log:
                logger.error(f"ErrorDetail: {log['errorDetail']}")
                sys.exit(1)
        build_duration = time.time() - build_start_time
        if not image_built:
            logger.error("Failed to build Docker image.")
            sys.exit(1)
        logger.info(f"Building Docker image took {build_duration:.2f} seconds.")
    except errors.BuildError as e:
        logger.error(f"BuildError: {e}")
        sys.exit(1)
    except errors.APIError as e:
        logger.error(f"APIError: {e}")
        sys.exit(1)

    # Tag the Docker image with the additional tag
    try:
        client.tag('nim-shim:latest', repository=SG_EP_CONTAINER)
    except errors.APIError as e:
        logger.error(f"Failed to tag image: {e}")
        sys.exit(1)

    # Push the Docker image to the registry
    logger.info("Pushing Docker image to registry...")
    push_start_time = time.time()
    try:
        push_logs = client.push(SG_EP_CONTAINER, stream=True, decode=True)
        for log in push_logs:
            status = log.get('status', '')
            if 'Waiting' not in status and 'Preparing' not in status and 'Layer already exists' not in status:
                logger.info(status)
        push_duration = time.time() - push_start_time
        logger.info(f"Pushing Docker image took {push_duration:.2f} seconds.")
    except errors.APIError as e:
        logger.error(f"Failed to push image: {e}")
        sys.exit(1)

    duration = time.time() - start_time
    logger.info(f"Creating and pushing shim image took {duration:.2f} seconds.")

def create_shim_endpoint():
    start_time = time.time()
    create_shim_image()

    # Create Model JSON
    model_json = {
        "ModelName": SG_EP_NAME,
        "PrimaryContainer": {
            "Image": SG_EP_CONTAINER,
            "Mode": "SingleModel",
            "Environment": {
                "NGC_API_KEY": os.environ.get('NGC_API_KEY')
            }
        },
        "ExecutionRoleArn": SG_EXEC_ROLE_ARN,
        "EnableNetworkIsolation": False
    }

    with open('sg-model.json', 'w') as f:
        json.dump(model_json, f)

    sagemaker_client.create_model(ModelName=SG_EP_NAME, PrimaryContainer=model_json['PrimaryContainer'], ExecutionRoleArn=SG_EXEC_ROLE_ARN)

    # Create Production Variant JSON
    prod_variant_json = [
        {
            "VariantName": "AllTraffic",
            "ModelName": SG_EP_NAME,
            "InstanceType": SG_INST_TYPE,
            "InitialInstanceCount": 1,
            "InitialVariantWeight": 1.0
        }
    ]

    # Create Endpoint Config
    sagemaker_client.create_endpoint_config(EndpointConfigName=SG_EP_NAME, ProductionVariants=prod_variant_json)

    # Create Endpoint
    sagemaker_client.create_endpoint(EndpointName=SG_EP_NAME, EndpointConfigName=SG_EP_NAME)

    # Wait for endpoint to be in service
    logger.info("Waiting for endpoint to be in service...")
    waiter = sagemaker_client.get_waiter('endpoint_in_service')
    waiter_start_time = time.time()
    waiter.wait(EndpointName=SG_EP_NAME, WaiterConfig={'Delay': 30, 'MaxAttempts': 60})
    waiter_duration = time.time() - waiter_start_time
    logger.info(f"Waiting for endpoint to be in service took {waiter_duration:.2f} seconds.")

    total_duration = time.time() - start_time
    logger.info(f"Creating and deploying shim endpoint took {total_duration:.2f} seconds.")

def render_template(template_file, output_file, context):
    env = Environment(loader=FileSystemLoader('templates'))
    template = env.get_template(template_file)
    rendered_content = template.render(context)
    with open(output_file, 'w') as f:
        f.write(rendered_content)

def test_endpoint():
    # Render test payload template
    context = {
        'SG_MODEL_NAME': SG_MODEL_NAME,
    }
    render_template(TEST_PAYLOAD_FILE, 'sg-invoke-payload.json', context)

    # Load test payload JSON from rendered file
    with open('sg-invoke-payload.json', 'r') as f:
        test_payload_json = json.load(f)

    # Invoke Endpoint
    start_time = time.time()
    response = sagemaker_runtime_client.invoke_endpoint(
        EndpointName=SG_EP_NAME,
        Body=json.dumps(test_payload_json),
        ContentType='application/json',
        Accept='application/json'
    )

    response_body = response['Body'].read().decode('utf-8')

    with open('sg-invoke-output.json', 'w') as f:
        f.write(response_body)

    duration = time.time() - start_time
    logger.info(f"Invocation of endpoint took {duration:.2f} seconds.")
    logger.info("Invocation output: %s", response_body)

def main():
    parser = argparse.ArgumentParser(description="Manage SageMaker endpoints and Docker images.")
    parser.add_argument('--cleanup', action='store_true', help='Delete existing SageMaker resources.')
    parser.add_argument('--create-shim-endpoint', action='store_true', help='Build shim image and deploy as an endpoint.')
    parser.add_argument('--create-shim-image', action='store_true', help='Build shim image locally.')
    parser.add_argument('--test-endpoint', action='store_true', help='Test the deployed endpoint with a sample invocation.')
    parser.add_argument('--validate-prereq', action='store_true', help='Validate prerequisites: Docker and AWS credentials.')

    parser.add_argument('--src-image-path', default=os.getenv('SRC_IMAGE_PATH', DEFAULT_SRC_IMAGE_PATH), help='Source image path')
    parser.add_argument('--dst-registry', default=os.getenv('DST_REGISTRY', DEFAULT_DST_REGISTRY), help='Destination registry')
    parser.add_argument('--sg-ep-name', default=None, help='SageMaker endpoint name')
    parser.add_argument('--sg-inst-type', default=os.getenv('SG_INST_TYPE', DEFAULT_SG_INST_TYPE), help='SageMaker instance type')
    parser.add_argument('--sg-exec-role-arn', default=os.getenv('SG_EXEC_ROLE_ARN', DEFAULT_SG_EXEC_ROLE_ARN), help='SageMaker execution role ARN')
    parser.add_argument('--sg-container-startup-timeout', type=int, default=int(os.getenv('SG_CONTAINER_STARTUP_TIMEOUT', DEFAULT_SG_CONTAINER_STARTUP_TIMEOUT)), help='SageMaker container startup timeout')
    parser.add_argument('--aws-region', default=os.getenv('AWS_REGION', DEFAULT_AWS_REGION), help='AWS region')
    parser.add_argument('--test-payload-file', default='sg-invoke-payload.json', help='Test payload template file')
    parser.add_argument('--sg-model-name', default=os.getenv('SG_MODEL_NAME', 'default-model-name'), help='SageMaker model name')

    args = parser.parse_args()

    global SRC_IMAGE_PATH, SRC_IMAGE_NAME, DST_REGISTRY, SG_EP_NAME, SG_EP_CONTAINER, SG_INST_TYPE, SG_EXEC_ROLE_ARN, SG_CONTAINER_STARTUP_TIMEOUT, AWS_REGION, TEST_PAYLOAD_FILE, SG_MODEL_NAME
    global sagemaker_client, sagemaker_runtime_client

    SRC_IMAGE_PATH = args.src_image_path
    SRC_IMAGE_NAME = SRC_IMAGE_PATH.split('/')[-1].split(':')[0]
    DST_REGISTRY = args.dst_registry
    SG_EP_NAME = args.sg_ep_name or os.getenv('SG_EP_NAME', f'nim-llm-{SRC_IMAGE_NAME}')
    SG_EP_CONTAINER = f'{DST_REGISTRY}:{SRC_IMAGE_NAME}'
    SG_INST_TYPE = args.sg_inst_type
    SG_EXEC_ROLE_ARN = args.sg_exec_role_arn
    SG_CONTAINER_STARTUP_TIMEOUT = args.sg_container_startup_timeout
    AWS_REGION = args.aws_region
    TEST_PAYLOAD_FILE = args.test_payload_file
    SG_MODEL_NAME = args.sg_model_name

    sagemaker_client = init_boto3_client('sagemaker')
    sagemaker_runtime_client = init_boto3_client('sagemaker-runtime')

    if args.cleanup:
        delete_sagemaker_resources(SG_EP_NAME)
    elif args.create_shim_endpoint:
        create_shim_endpoint()
    elif args.create_shim_image:
        create_shim_image()
    elif args.test_endpoint:
        test_endpoint()
    elif args.validate_prereq:
        validate_prereq()
    else:
        parser.print_help()

if __name__ == '__main__':
    main()
