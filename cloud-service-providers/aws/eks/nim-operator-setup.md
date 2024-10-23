# NVIDIA NIM Operator on AWS EKS:

Please see the NIM Operator documentation before you proceed: https://docs.nvidia.com/nim-operator/latest/index.html
This repository is dedicated to testing NVIDIA NIM Operator on AWS EKS (Elastic Kubernetes Service).

## Cluster setup for inference:

To install the pre-requisites for the NIM Operator, please follow the steps below:

1: Install the GPU Operator. https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html#procedure

    helm install --wait --generate-name -n gpu-operator --create-namespace nvidia/gpu-operator --version=v23.6.0 --set toolkit.enabled=false
   
2: Follow the instructions for the NIM Operator installation: https://docs.nvidia.com/nim-operator/latest/install.html#install-nim-operator


# Caching Models

1.     bash setup/setup.sh

    Note: This setup script (directory: nim-deploy/setup)creates two storage classes- EFS and EBS. The necessary csi drivers are installed as add-ons by the CDK.

2.  Follow the instructions in the docs (https://docs.nvidia.com/nim-operator/latest/cache.html#procedure) using the sample yaml files below.
   
    a) EBS volume:

         kubectl apply -n nim-service -f storage/nim-operator-nim-cache-ebs.yaml

    b) EFS storage:

         kubectl apply -n nim-service -f storage/nim-operator-nim-cache-efs.yaml

 
# Creating a NIM Service 

1. Follow the instructions in the [docs](https://docs.nvidia.com/nim-operator/latest/service.html#procedure) using the sample yaml file below.

         kubectl apply -n nim-service -f storage/nim-operator-nim-service.yaml
   
2. Use ingress.yaml to add an alb ingress controller.

         kubectl apply -f ingress.yaml -n nim-service

# Sample request and response:

Get the DNS of the Load Balancer created in the previous step:
```
ELB_DNS=$(aws elbv2 describe-load-balancers --query "LoadBalancers[*].{DNSName:DNSName}")
```
Send as sample request:

```
curl -X 'POST' \
  "http://${ELB_DNS}/v1/chat/completions" \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
    "messages": [
    {
        "content": "You are a polite and respectful chatbot helping people plan a vacation.",
        "role": "system"
    },
    {
        "content": "What should I do for a 4 day vacation in Spain?",
        "role": "user"
    }
   ],
   "model": "meta/llama3-8b-instruct",
   "max_tokens": 16,
   "top_p": 1,
   "n": 1,
   "stream": false,
   "stop": "\n",
   "frequency_penalty": 0.0
}'

```
Response:

```
    {
    "id": "cmpl-ba02077a544e411f8ba2ff9f38a6917a",
    "object": "chat.completion",
    "created": 1717642306,
    "model": "meta/llama3-8b-instruct",
    "choices": [
        {
            "index": 0,
            "message": {
                "role": "assistant",
                "content": "Spain is a wonderful destination! With four days, you can easily explore one or"
            },
            "logprobs": null,
            "finish_reason": "length",
            "stop_reason": null
        }
    ],
    "usage": {
        "prompt_tokens": 42,
        "total_tokens": 58,
        "completion_tokens": 16
    }
}
```

# Gen-ai perf tool

      kubectl apply -f perf/gen-ai-perf.yaml

exec into the triton pod

      kubectl exec -it triton -- bash

Run the following command

      NIM_MODEL_NAME="meta/llama3-8b-instruct"
      server_url=http://nim-llm-service:8000
      concurrency=20
      input_tokens=128
      output_tokens=10

      genai-perf -m $NIM_MODEL_NAME --endpoint v1/chat/completions --endpoint-type chat \
      --service-kind openai --streaming \
      -u $server_url \
      --num-prompts 100 --prompt-source synthetic \
      --synthetic-input-tokens-mean $input_tokens \
      --synthetic-input-tokens-stddev 50 \
      --concurrency $concurrency \
      --extra-inputs max_tokens:$output_tokens \
      --extra-input ignore_eos:true \
      --profile-export-file test_chat_${concurrency}
