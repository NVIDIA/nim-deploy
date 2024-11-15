# NVIDIA NIM Operator on Azure AKS:

Please see the NIM Operator documentation before you proceed: https://docs.nvidia.com/nim-operator/latest/index.html
The files in this repo are for reference, for the official NVIDIA AI Enterprise supported release, see NGC and the official documentation.
Helm a and GPU Operator should be installed in the cluster before proceeding with the steps below. 
Pre-requisites: https://docs.nvidia.com/nim-operator/latest/install.html#prerequisites

Follow the instructions for the NIM Operator installation: https://docs.nvidia.com/nim-operator/latest/install.html#install-nim-operator


# Caching Models

1.     Set your NGC_API_KEY and create secrets as show below:


If you have not set up NGC, see the [NGC Setup](https://ngc.nvidia.com/setup) topic.
Set the **NGC_API_KEY** environment variable to your NGC API key, as shown in the following example.

```bash
export NGC_API_KEY="key from ngc"
```



2.  Follow the instructions in the docs (https://docs.nvidia.com/nim-operator/latest/cache.html#procedure) using the sample yaml files below.
   
The image and the model files are fairly large (> 10GB, typically), so ensure that however you are managing the storage for your helm release, you have enough space to host both the image. If you have a persistent volume setup available to you, as you do in most cloud providers, it is recommended that you use it. If you need to be able to deploy pods quickly and would like to be able to skip the model download step, there is an advantage to using a shared volume such as NFS as your storage setup. To try this out, it is simplest to use a normal persistent volume claim. See the Kubernetes Persistent Volumes documentation for more information.
 
# Creating a NIM Service 

1. Follow the instructions in the [docs](https://docs.nvidia.com/nim-operator/latest/service.html#procedure) using the sample yaml file below.

         kubectl apply -n nim-service -f storage/nim-operator-nim-service.yaml
   
2. Use ingress.yaml to add an  ingress controller.

         kubectl apply -f ingress.yaml -n nim-service

# Sample request and response:

Get the DNS of the Load Balancer created in the previous step:
```
ELB_DNS=$()
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
