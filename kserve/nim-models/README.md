# NIM Models
This directory holds NIM `InferenceService` YAML specs, these should be applied by data scientist or anyone looking to instantiate a NIM into a cluster.

The NIM specs provided here are a set of examples. These examples could be modified to use different combinations of GPUs or models as specified by the official [NIM support matrix](https://docs.nvidia.com/nim/large-language-models/latest/support-matrix.html).

## NIM Profile
By default, the NIM will select the underlying model profile that is most available for the hardware the NIM was deployed on. This may include the quantization method, tensor parallelism, inferencing backend, or other parameters.

The profile can be overriden in NIM by setting the `NIM_MODEL_PROFILE` environment variable. The value can be set to either the human readable name such as `vllm-fp16-tp2` or the longer machine-readable hash (see the [here](https://docs.nvidia.com/nim/large-language-models/latest/getting-started.html#serving-models-from-local-assets) for details on profiles). This can be done in the KServe `InferenceService` by adding a `env` section under the spec.predictor.model section of the yaml such as:

**Specify the Tensor Parallelism 2, FP16, with vLLM backend**
```
spec:
  predictor:
    model:
      env:
        - name: NIM_MODEL_PROFILE
          value: vllm-fp16-tp2
```

## GPU Count
GPU count can be specified by changing both the `limits` and `requests` under the `resources` section of the `InferenceService` YAML file.

**Specify 2 GPUs**
```
      resources:
        limits:
          nvidia.com/gpu: "2"
        requests:
          nvidia.com/gpu: "2"
```


**Specify 1 GPU**
```
      resources:
        limits:
          nvidia.com/gpu: "1"
        requests:
          nvidia.com/gpu: "1"
```

## GPU Type
GPU Type can be specified by specifying the `nvidia.com/gpu.product` or another node label under the `nodeSelector` section of the `InferenceService` YAML file. These Node labels come from the GPU Feature Discovery tool, which is part of the GPU Operator. A full list of these labels and different GPU types can be found in the NVIDIA docs.

To use any GPU available, omit the `nodeSelector` field. This is only recommended in homogenous clusters with suitable GPUs for the deployed workloads.

**Specify H100 80GB SXM GPU as a requirement**
```
    nodeSelector:
      nvidia.com/gpu.product: H100-SXM4-80GB
```

**Specify A100 80GB SXM GPU as a requirement**
```
    nodeSelector:
      nvidia.com/gpu.product: A100-SXM4-80GB
```

**Specify A100 80GB PCIE GPU as a requirement**
```
    nodeSelector:
      nvidia.com/gpu.product=NVIDIA-A100-PCIE-80GB
```
> * Note: In certain CSPs or environments these labels may appear different. To determine the proper values to use run `kubectl describe nodes` in the cluster.

## Autoscaling Target

The default autoscaling behaviour of KServe monitors the size of the queue to the `InferenceService` and tries to load balance the requests across the Pods such that no single Pod has more than `autoscaling.knative.dev/target` threads sent to it.

For example, if `autoscaling.knative.dev/target` is set to `10` and the request queue is constantly at `99`, KServe will attempt to launch 10 `InferenceService` Pods so that each Pod serves 9 requests.

This number can be tuned for each `InferenceService`.

**10  Inference requests per Pod**
```
    autoscaling.knative.dev/target: "10"
```

**100  Inference requests per Pod**
```
    autoscaling.knative.dev/target: "100"
```
