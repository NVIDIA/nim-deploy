# NVIDIA NIM Deployment on SageMaker with S3 NIM Storage

## Overview

NVIDIA NIM, a component of NVIDIA AI Enterprise, enhances your applications with the power of state-of-the-art large language models (LLMs), providing unmatched natural language processing and understanding capabilities. Whether you're developing chatbots, content analyzers, or any application that needs to understand and generate human language, NVIDIA NIM has you covered.

To deploy a NVIDIA NIM, the NIM profiles are typically downlaoded from [NVIDIA GPU Cloud (NGC)](https://catalog.ngc.nvidia.com/). The model profiles typically includes model weights and the optimizations based on the GPU hardware the NIM is deployed on. When the VPC configuration is private with no internet connectivity, the NIM assets can be stored in S3 and retrieved there during deployment using S3 VPC endpoints time instead of fetching them directly from NGC. This can also offer improved latency since traffic only traverses within the AWS network.


## 1. login into NGC to pull the NIM container
```bash
$ docker login nvcr.io
username: $oauthtoken
password: <NGC API KEY>
```

## 2. Download NIM model profiles to local cache

The below steps shows the steps for the Llama3.2 1B Embedding v2 NIM. For any other NIM, the steps would be similar as well

**Note: It is recommended to run these steps on an EC2 instance with IAM instance profile for easy AWS credential management and to meet the compute requirements (Using a GPU Instance) to download the NIM profiles. Ensure the Instance Volume is large enough to download all NIM profiles and docker images.**

### 1. Export your NGC API key as an environment variable:
```bash
$ export NGC_API_KEY=<NGC API KEY>
```

### 2. Run the NIM container image locally, list the model profiles, and download the model profiles

- Start the container
```bash 
# Choose a LLM NIM Image from NGC
$ export IMG_NAME="nvcr.io/nim/nvidia/llama-3.2-nv-embedqa-1b-v2:1.3.0"

$ export LOCAL_NIM_CACHE=./llama3_2_1b_embedqa/nim
$ mkdir -p "$LOCAL_NIM_CACHE"

$ docker run -it --rm \
  --runtime=nvidia \
  --gpus all \
  --shm-size=16GB \
  -e NGC_API_KEY=$NGC_API_KEY \
  -v "$LOCAL_NIM_CACHE:/opt/nim/.cache" \
  -u $(id -u) \
  $IMG_NAME \
  bash
```

- List the model profiles. See [here](https://docs.nvidia.com/nim/large-language-models/latest/utilities.html#list-available-model-profiles) for details on the command
```bash
$ list-model-profiles
```
Partial Output
```
...
MODEL PROFILES
- Compatible with system and runnable:
 - 737a0c2191e21c442c4b041bddbd7099681cc5b8aeb42c8f992311b807f8d5d3 (l4-fp8-tensorrt-tensorrt)
...
```

- Download the model profiles to local cache. See [here](https://docs.nvidia.com/nim/large-language-models/latest/utilities.html#download-model-profiles-to-nim-cache) for details on the command
**Note: You have to run the below command for each profile to download**
```bash
$ download-to-cache --profile 407c...
```

- Exit the container
```bash
$ exit
```

## 3. Upload NIM local cache to S3 bucket
- Create a directory in the S3 bucket to store the NIM files. **This directory can be any name you wish**
```bash
$ aws s3api put-object --bucket <ENTER S3 BUCKET NAME> --key llama-3.2-nv-embedqa-1b-v2-1.3.0/
```

- Upload the NIM files to the S3 bucket
```bash
$ aws s3 cp --recursive ./llama3_2_1b_embedqa/nim/ s3://<ENTER S3 BUCKET NAME>/llama-3.2-nv-embedqa-1b-v2-1.3.0/
```

## 4. Test Sagemaker endpoint deployment

**Note: The notebook was tested on a SageMaker notebook instance**

After uploading the NIM files to S3, run through the [notebook](./s3_nim_sagemaker.ipynb) to test that deployment with the NIM files on S3 works on SageMaker
    


