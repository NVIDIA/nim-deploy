import os
import sys
import json
import argparse
import boto3
import subprocess
import requests
import logging
import time
from sagemaker.base_deserializers import StreamDeserializer
from sagemaker.predictor import Predictor
from sagemaker.session import Session
from sagemaker.serializers import JSONSerializer
from jinja2 import Environment, FileSystemLoader, TemplateNotFound
from botocore.exceptions import ClientError

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
def init_boto3_client(service_name, region_name=DEFAULT_AWS_REGION):
    return boto3.client(
        service_name,
        region_name=region_name
    )

sagemaker_client = None
sagemaker_runtime_client = None

# Docker operations using shell commands
def docker_login_ecr(region, registry):
    start_time = time.time()
    login_command = f"aws ecr get-login-password --region {region} | docker login --username AWS --password-stdin {registry}"
    subprocess.run(login_command, shell=True, check=True)
    end_time = time.time()
    logger.info(f"Docker login ECR completed in {end_time - start_time:.2f} seconds")

def docker_pull(image):
    start_time = time.time()
    pull_command = f"docker pull {image}"
    subprocess.run(pull_command, shell=True, check=True)
    end_time = time.time()
    logger.info(f"Docker pull completed in {end_time - start_time:.2f} seconds")

def docker_build_and_push(dockerfile, tags, registries):
    start_time = time.time()
    docker_login_ecr(AWS_REGION, DST_REGISTRY)
    docker_pull(SRC_IMAGE_PATH)

    env = Environment(loader=FileSystemLoader('.'))
    template = env.get_template('Dockerfile')  # Ensure your template is named Dockerfile.j2
    dockerfile_content = template.render(SRC_IMAGE=SRC_IMAGE_PATH)

    with open('Dockerfile.nim', 'w') as f:
        f.write(dockerfile_content)

    required_files = ['launch.sh', 'caddy-config.json']
    missing_files = [f for f in required_files if not os.path.exists(f)]
    if missing_files:
        logger.error(f"Missing required files for Docker build: {missing_files}")
        sys.exit(1)
    
    logger.info("All required files are present for Docker build.")
    logger.info("Dockerfile.nim content:")
    with open('Dockerfile.nim', 'r') as f:
        logger.info(f.read())

    build_command = f"docker build -t {tags[0]} -f Dockerfile.nim ."
    subprocess.run(build_command, shell=True, check=True)

    for tag in tags[1:]:
        tag_command = f"docker tag {tags[0]} {tag}"
        subprocess.run(tag_command, shell=True, check=True)

    for registry in registries:
        docker_login_ecr(AWS_REGION, registry)
        for tag in tags:
            push_command = f"docker push {tag}"
            subprocess.run(push_command, shell=True, check=True)
    
    end_time = time.time()
    logger.info(f"Docker build and push completed in {end_time - start_time:.2f} seconds")

def validate_prereq():
    start_time = time.time()
    try:
        docker_login_ecr(AWS_REGION, DST_REGISTRY)
        logger.info("Docker credentials are valid.")
    except Exception as e:
        logger.error(f"Error validating Docker credentials: {e}")
        sys.exit(1)

    try:
        sts_client = boto3.client('sts', region_name=AWS_REGION)
        sts_client.get_caller_identity()
        logger.info("AWS credentials are valid.")
    except ClientError as e:
        logger.error(f"Error validating AWS credentials: {e}")
        sys.exit(1)

    end_time = time.time()
    logger.info(f"Prerequisite validation completed in {end_time - start_time:.2f} seconds")

def delete_sagemaker_resources(endpoint_name):
    def delete_resource(delete_func, resource_type, resource_name):
        start_time = time.time()
        try:
            delete_func()
            logger.info(f"Deleted {resource_type}: {resource_name}")
        except ClientError as e:
            if e.response['Error']['Code'] == 'ValidationException' and 'Could not find' in e.response['Error']['Message']:
                logger.info(f"{resource_type} {resource_name} does not exist.")
            else:
                logger.error(f"Error deleting {resource_type} {resource_name}: {e}")
        end_time = time.time()
        logger.info(f"Deletion of {resource_type} {resource_name} completed in {end_time - start_time:.2f} seconds")

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

def create_shim_image():
    start_time = time.time()
    docker_login_ecr(AWS_REGION, DST_REGISTRY)
    docker_pull(SRC_IMAGE_PATH)

    env = Environment(loader=FileSystemLoader('.'))
    template = env.get_template('Dockerfile')  # Ensure your template is named Dockerfile.j2
    dockerfile_content = template.render(SRC_IMAGE=SRC_IMAGE_PATH)

    with open('Dockerfile.nim', 'w') as f:
        f.write(dockerfile_content)

    required_files = ['launch.sh', 'caddy-config.json']
    missing_files = [f for f in required_files if not os.path.exists(f)]
    if missing_files:
        logger.error(f"Missing required files for Docker build: {missing_files}")
        sys.exit(1)
    
    logger.info("All required files are present for Docker build.")
    logger.info("Dockerfile.nim content:")
    with open('Dockerfile.nim', 'r') as f:
        logger.info(f.read())

    build_command = f"docker build -t nim-shim:latest -f Dockerfile.nim ."
    subprocess.run(build_command, shell=True, check=True)

    tag_command = f"docker tag nim-shim:latest {SG_EP_CONTAINER}"
    subprocess.run(tag_command, shell=True, check=True)

    push_command = f"docker push {SG_EP_CONTAINER}"
    subprocess.run(push_command, shell=True, check=True)

    end_time = time.time()
    logger.info(f"Shim image creation completed in {end_time - start_time:.2f} seconds")

def create_shim_endpoint():
    start_time = time.time()

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

    sagemaker_client.create_model(ModelName=SG_EP_NAME, PrimaryContainer=model_json['PrimaryContainer'], ExecutionRoleArn=SG_EXEC_ROLE_ARN)

    prod_variant_json = [
        {
            "VariantName": "AllTraffic",
            "ModelName": SG_EP_NAME,
            "InstanceType": SG_INST_TYPE,
            "InitialInstanceCount": 1,
            "InitialVariantWeight": 1.0
        }
    ]

    sagemaker_client.create_endpoint_config(EndpointConfigName=SG_EP_NAME, ProductionVariants=prod_variant_json)

    sagemaker_client.create_endpoint(EndpointName=SG_EP_NAME, EndpointConfigName=SG_EP_NAME)

    logger.info("Waiting for endpoint to be in service...")
    waiter = sagemaker_client.get_waiter('endpoint_in_service')
    waiter.wait(EndpointName=SG_EP_NAME, WaiterConfig={'Delay': 30, 'MaxAttempts': 60})

    end_time = time.time()
    logger.info(f"Shim endpoint creation completed in {end_time - start_time:.2f} seconds")

def render_template(template_file, output_file, context):
    start_time = time.time()
    env = Environment(loader=FileSystemLoader(os.path.dirname(template_file)))
    try:
        template = env.get_template(os.path.basename(template_file))
        rendered_content = template.render(context)
        with open(output_file, 'w') as f:
            f.write(rendered_content)
        logger.info(f"Successfully rendered template {template_file} to {output_file}")
    except TemplateNotFound:
        logger.error(f"Template not found: {template_file}")
        sys.exit(1)
    end_time = time.time()
    logger.info(f"Template rendering completed in {end_time - start_time:.2f} seconds")

def test_endpoint(print_raw):
    start_time = time.time()
    context = {
        'SG_MODEL_NAME': SG_MODEL_NAME,
    }
    render_template(TEST_PAYLOAD_FILE, 'sg-invoke-payload.json', context)

    try:
        with open('sg-invoke-payload.json', 'r') as f:
            test_payload_json = json.load(f)
    except json.JSONDecodeError as e:
        logger.error(f"Failed to load JSON from sg-invoke-payload.json: {e}")
        sys.exit(1)

    test_payload_json['stream'] = True

    session = boto3.Session(region_name=AWS_REGION)
    smr = session.client('sagemaker-runtime')
    response = smr.invoke_endpoint_with_response_stream(
        EndpointName=SG_EP_NAME,
        Body=json.dumps(test_payload_json),
        ContentType='application/json'
    )

    event_stream = response['Body']
    accumulated_data = ""
    start_marker = 'data:'
    end_marker = '"finish_reason":null}]}'

    for event in event_stream:
        try:
            payload = event.get('PayloadPart', {}).get('Bytes', b'')
            if payload:
                data_str = payload.decode('utf-8')
                if print_raw:
                    print(data_str, flush=True)

                accumulated_data += data_str

                while start_marker in accumulated_data and end_marker in accumulated_data:
                    start_idx = accumulated_data.find(start_marker)
                    end_idx = accumulated_data.find(end_marker) + len(end_marker)
                    full_response = accumulated_data[start_idx + len(start_marker):end_idx]
                    accumulated_data = accumulated_data[end_idx:]

                    try:
                        data = json.loads(full_response)
                        content = data.get('choices', [{}])[0].get('delta', {}).get('content', "")
                        if content:
                            print(content, end='', flush=True)
                    except json.JSONDecodeError:
                        continue
        except Exception as e:
            print(f"\nError processing event: {e}", flush=True)
            continue

    end_time = time.time()
    logger.info(f"Endpoint test (stream) completed in {end_time - start_time:.2f} seconds")

def test_endpoint_no_stream(print_raw):
    start_time = time.time()
    context = {
        'SG_MODEL_NAME': SG_MODEL_NAME,
    }
    render_template(TEST_PAYLOAD_FILE, 'sg-invoke-payload.json', context)

    try:
        with open('sg-invoke-payload.json', 'r') as f:
            test_payload_json = json.load(f)
    except json.JSONDecodeError as e:
        logger.error(f"Failed to load JSON from sg-invoke-payload.json: {e}")
        sys.exit(1)

    session = boto3.Session(region_name=AWS_REGION)
    smr = session.client('sagemaker-runtime')
    response = smr.invoke_endpoint(
        EndpointName=SG_EP_NAME,
        Body=json.dumps(test_payload_json),
        ContentType='application/json'
    )

    response_body = response['Body'].read().decode('utf-8')
    if print_raw:
        print(response_body, flush=True)

    try:
        data = json.loads(response_body)
        content = data.get('choices', [{}])[0].get('delta', {}).get('content', "")
        if content:
            print(content, end='', flush=True)
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse JSON response: {e}")

    end_time = time.time()
    logger.info(f"Endpoint test (no stream) completed in {end_time - start_time:.2f} seconds")

def test_apicat_endpoint(print_raw, api_url, api_key):
    start_time = time.time()
    context = {
        'SG_MODEL_NAME': SG_MODEL_NAME,
    }
    render_template(TEST_PAYLOAD_FILE, 'sg-invoke-payload.json', context)

    try:
        with open('sg-invoke-payload.json', 'r') as f:
            test_payload_json = json.load(f)
    except json.JSONDecodeError as e:
        logger.error(f"Failed to load JSON from sg-invoke-payload.json: {e}")
        sys.exit(1)

    test_payload_json['stream'] = True

    headers = {
        "accept": "application/json",
        "content-type": "application/json",
        "authorization": f"Bearer {api_key}"
    }

    response = requests.post(api_url, json=test_payload_json, headers=headers, stream=True)

    if response.status_code != 200:
        print(f"Error: {response.status_code} - {response.text}")
        return

    accumulated_data = ""
    start_marker = 'data:'
    end_marker = '"finish_reason":null}]}'

    for chunk in response.iter_content(chunk_size=None):
        if chunk:
            data_str = chunk.decode('utf-8')
            if print_raw:
                print(data_str, flush=True)

            accumulated_data += data_str

            while start_marker in accumulated_data and end_marker in accumulated_data:
                start_idx = accumulated_data.find(start_marker)
                end_idx = accumulated_data.find(end_marker) + len(end_marker)
                full_response = accumulated_data[start_idx + len(start_marker):end_idx]
                accumulated_data = accumulated_data[end_idx:]

                try:
                    data = json.loads(full_response)
                    content = data.get('choices', [{}])[0].get('delta', {}).get('content', "")
                    if content:
                        print(content, end='', flush=True)
                except json.JSONDecodeError:
                    continue

    end_time = time.time()
    logger.info(f"API Catalog endpoint test completed in {end_time - start_time:.2f} seconds")

def test_local_endpoint(print_raw, api_url):
    start_time = time.time()
    context = {
        'SG_MODEL_NAME': SG_MODEL_NAME,
    }
    render_template(TEST_PAYLOAD_FILE, 'sg-invoke-payload.json', context)

    try:
        with open('sg-invoke-payload.json', 'r') as f:
            test_payload_json = json.load(f)
    except json.JSONDecodeError as e:
        logger.error(f"Failed to load JSON from sg-invoke-payload.json: {e}")
        sys.exit(1)

    test_payload_json['stream'] = True

    headers = {
        "accept": "application/json",
        "content-type": "application/json"
    }

    response = requests.post(api_url, json=test_payload_json, headers=headers, stream=True)

    if response.status_code != 200:
        print(f"Error: {response.status_code} - {response.text}")
        return

    accumulated_data = ""
    start_marker = 'data:'
    end_marker = '"finish_reason":null}]}'

    for chunk in response.iter_content(chunk_size=None):
        if chunk:
            data_str = chunk.decode('utf-8')
            if print_raw:
                print(data_str, flush=True)

            accumulated_data += data_str

            while start_marker in accumulated_data and end_marker in accumulated_data:
                start_idx = accumulated_data.find(start_marker)
                end_idx = accumulated_data.find(end_marker) + len(end_marker)
                full_response = accumulated_data[start_idx + len(start_marker):end_idx]
                accumulated_data = accumulated_data[end_idx:]

                try:
                    data = json.loads(full_response)
                    content = data.get('choices', [{}])[0].get('delta', {}).get('content', "")
                    if content:
                        print(content, end='', flush=True)
                except json.JSONDecodeError:
                    continue

    end_time = time.time()
    logger.info(f"Local endpoint test completed in {end_time - start_time:.2f} seconds")

def main():
    parser = argparse.ArgumentParser(description="Manage SageMaker endpoints and Docker images.")
    parser.add_argument('--cleanup', action='store_true', help='Delete existing SageMaker resources.')
    parser.add_argument('--create-shim-endpoint', action='store_true', help='Build shim image and deploy as an endpoint.')
    parser.add_argument('--create-shim-image', action='store_true', help='Build shim image locally.')
    parser.add_argument('--test-endpoint', action='store_true', help='Test the deployed endpoint with a sample invocation.')
    parser.add_argument('--test-endpoint-nostream', action='store_true', help='Test the deployed endpoint with a sample invocation without streaming.')
    parser.add_argument('--test-api-catalog-endpoint', action='store_true', help='Test the deployed endpoint with a sample invocation.')
    parser.add_argument('--test-local-endpoint', action='store_true', help='Test a local NIM endpoint with a sample invocation.')
    parser.add_argument('--test-local-url', default="http://127.0.0.1:8080/invocations", help='Target a specific local endpoint URL')
    parser.add_argument('--validate-prereq', action='store_true', help='Validate prerequisites: Docker and AWS credentials.')
    parser.add_argument('--print-raw', action='store_true', help='Print the raw payload received from the endpoint.')

    parser.add_argument('--src-image-path', default=os.getenv('SRC_IMAGE_PATH', DEFAULT_SRC_IMAGE_PATH), help='Source image path')
    parser.add_argument('--dst-registry', default=os.getenv('DST_REGISTRY', DEFAULT_DST_REGISTRY), help='Destination registry')
    parser.add_argument('--image-registry', default=None, help='Comma-separated list of additional image registries')
    parser.add_argument('--sg-ep-name', default=None, help='SageMaker endpoint name')
    parser.add_argument('--sg-inst-type', default=os.getenv('SG_INST_TYPE', DEFAULT_SG_INST_TYPE), help='SageMaker instance type')
    parser.add_argument('--sg-exec-role-arn', default=os.getenv('SG_EXEC_ROLE_ARN', DEFAULT_SG_EXEC_ROLE_ARN), help='SageMaker execution role ARN')
    parser.add_argument('--sg-container-startup-timeout', type=int, default=int(os.getenv('SG_CONTAINER_STARTUP_TIMEOUT', DEFAULT_SG_CONTAINER_STARTUP_TIMEOUT)), help='SageMaker container startup timeout')
    parser.add_argument('--aws-region', default=os.getenv('DEFAULT_AWS_REGION', DEFAULT_AWS_REGION), help='AWS region')
    parser.add_argument('--test-payload-file', default='templates/sg-test-payload.json.j2', help='Test payload template file')
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

    image_registries = [DST_REGISTRY]
    if args.image_registry:
        image_registries.extend(args.image_registry.split(','))

    sagemaker_client = init_boto3_client('sagemaker', AWS_REGION)
    sagemaker_runtime_client = init_boto3_client('sagemaker-runtime', AWS_REGION)

    if args.cleanup:
        delete_sagemaker_resources(SG_EP_NAME)
    elif args.create_shim_endpoint:
        create_shim_endpoint()
    elif args.create_shim_image:
        docker_build_and_push('Dockerfile', [SG_EP_CONTAINER], image_registries)
    elif args.test_endpoint:
        test_endpoint(args.print_raw)
    elif args.test_endpoint_nostream:
        test_endpoint_no_stream(args.print_raw)
    elif args.test_api_catalog_endpoint:
        api_key = os.environ.get('NV_API_KEY')
        api_url = "https://integrate.api.nvidia.com/v1/chat/completions"
        test_apicat_endpoint(args.print_raw, api_url, api_key)
    elif args.test_local_endpoint:
        api_url = args.test_local_url
        test_local_endpoint(args.print_raw, api_url)
    elif args.validate_prereq:
        validate_prereq()
    else:
        parser.print_help()

if __name__ == '__main__':
    main()
