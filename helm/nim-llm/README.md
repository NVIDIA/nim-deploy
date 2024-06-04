# NIM-LLM Helm Chart

NVIDIA NIM for LLMs Helm Chart simplifies NIM deployment on Kubernetes. It aims to support deployment with a variety of possible cluster, GPU and storage confurations.

## Setting up the environment

This helm chart requires that you have a secret with your NGC API key configured for downloading private images, and one with your NGC API key (below named ngc-api). These will likely have the same key in it, but they will have different formats (dockerconfig.json vs opaque).

To deploy a NIM, some custom values are generally required. Typically, this looks similar to this, at a minimum:

```yaml
image:
    repository: "nvcr.io/nim/meta/llama3-8b-instruct" # container location
    tag: 1.0.0 # NIM version you want to deploy
model:
  ngcAPISecret: ngc-api  # name of a secret in the cluster that includes a key named NGC_CLI_API_KEY and is an NGC API key
resources:
  limits:
    nvidia.com/gpu: 1
  requests:
    nvidia.com/gpu: 1
persistence:
  enabled: true
  size: 30Gi
imagePullSecrets:
  - name: my-image-secret # secret created to pull nvcr.io images, see https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/
```

## Storage

Storage is a particular concern when setting up NIMs. Models can be quite large, and you can fill disk downloading things to emptyDirs or other locations around your pod image. It is best to ensure you have persistent storage of some kind mounted on your 
pod.

This chart supports four general categories of storage outside of the default of an emptyDir:
  1. Persistent Volume Claims (enabled with `persistence.enabled`)
  2. Persistent Volume Claim templates (enabled with `persistence.enabled` and `statefulSet.enabled`)
  3. Direct NFS (enabled with `nfs.enabled`)
  4. hostPath (enabled with `hostPath.enabled`)

The supported options for each are detailed in relevant section of Parameters below. These options are mutually exclusive. You should only enable *one* option. They represent different strategies of cluster management and scaling that should be considered before selecting. If in doubt or just creating a single pod, use persistent volumes.

See options below.

## Parameters

### Deployment parameters

| Name                              | Description                                                                                                                                                              | Value   |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------- |
| `affinity`                        | [default: {}] Affinity settings for deployment. Allows to constraint pods to nodes.                                                                                      | `{}`    |
| `containerSecurityContext`        | Specify privilege and access control settings for Container(Only affects the main container)                                                                             | `{}`    |
| `customCommand`                   | overrides command line options sent to the NeMo Inference service with the array listed here.                                                                            | `[]`    |
| `env`                             | Adds arbitrary environment variables to the main container                                                                                                               | `[]`    |
| `extraVolumes`                    | Adds arbitrary additional volumes to the deployment set definition                                                                                                       | `{}`    |
| `extraVolumeMounts`               | Specify volume mounts to the main container from extraVolumes                                                                                                            | `{}`    |
| `image.repository`                | NIM-LLM Image Repository                                                                                                                                                 | `""`    |
| `image.tag`                       | Image tag                                                                                                                                                                | `""`    |
| `image.pullPolicy`                | Image pull policy                                                                                                                                                        | `""`    |
| `imagePullSecrets`                | Specify list of secret names that are needed for the main container and any init containers.                                                                             |         |
| `initContainers`                  | Specify model init containers, select only one, if needed.                                                                                                               |         |
| `initContainers.ngcInit`          | Legacy containers only. Specify NGC init container. It should either have ngc cli pre-installed or wget + unzip pre-installed -- must not be musl-based (alpine).        | `{}`    |
| `initContainers.extraInit`        | Specify any additional init containers your use case requires.                                                                                                           | `{}`    |
| `healthPort`                      | Specify health check port. -- for use with models.legacyCompat only since current NIMs have no separate port                                                             | `""`    |
| `nodeSelector`                    | Specify labels to ensure that NeMo Inference is deployed only on certain nodes (likely best to set this to `nvidia.com/gpu.present: "true"` depending on cluster setup). | `{}`    |
| `podAnnotations`                  | Specify additional annotation to the main deployment pods                                                                                                                | `{}`    |
| `podSecurityContext`              | Specify privilege and access control settings for pod (Only affects the main pod).                                                                                       |         |
| `podSecurityContext.runAsUser`    | Specify user UID for pod.                                                                                                                                                | `1000`  |
| `podSecurityContext.runAsGroup`   | Specify group ID for pod.                                                                                                                                                | `1000`  |
| `podSecurityContext.fsGroup`      | Specify file system owner group id.                                                                                                                                      | `1000`  |
| `replicaCount`                    | Specify replica count for deployment.                                                                                                                                    | `1`     |
| `resources`                       | Specify resources limits and requests for the running service.                                                                                                           |         |
| `resources.limits.nvidia.com/gpu` | Specify number of GPUs to present to the running service.                                                                                                                | `1`     |
| `serviceAccount.create`           | Specifies whether a service account should be created.                                                                                                                   | `false` |
| `serviceAccount.annotations`      | Specifies annotations to be added to the service account.                                                                                                                | `{}`    |
| `serviceAccount.name`             | Specify name of the service account to use. If it is not set and create is true, a name is generated using a fullname template.                                          | `""`    |
| `statefulSet.enabled`             | Enables statefulset deployment. Enabling statefulSet allows PVC templates for scaling. If using central PVC with RWX accessMode, this isn't needed.                      | `true`  |
| `tolerations`                     | Specify tolerations for pod assignment. Allows the scheduler to schedule pods with matching taints.                                                                      |         |

### Autoscaling parameters

Values used for autoscaling. If autoscaling is not enabled, these are ignored.
They should be overridden on a per-model basis based on quality-of-service metrics as well as cost metrics.
This isn't recommended except with usage of the custom metrics API using something like the prometheus-adapter.
Standard metrics of CPU and memory are of limited use in scaling NIM

| Name                      | Description                               | Value   |
| ------------------------- | ----------------------------------------- | ------- |
| `autoscaling.enabled`     | Enable horizontal pod autoscaler.         | `false` |
| `autoscaling.minReplicas` | Specify minimum replicas for autoscaling. | `1`     |
| `autoscaling.maxReplicas` | Specify maximum replicas for autoscaling. | `10`    |
| `autoscaling.metrics`     | Array of metrics for autoscaling.         | `[]`    |

### Ingress parameters

| Name                                    | Description                                                                                                   | Value                    |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------- | ------------------------ |
| `ingress.enabled`                       | Enables ingress.                                                                                              | `false`                  |
| `ingress.className`                     | Specify class name for Ingress.                                                                               | `""`                     |
| `ingress.annotations`                   | Specify additional annotations for ingress.                                                                   | `{}`                     |
| `ingress.hosts`                         | Specify list of hosts each containing lists of paths.                                                         |                          |
| `ingress.hosts[0].host`                 | Specify name of host.                                                                                         | `chart-example.local`    |
| `ingress.hosts[0].paths[0].path`        | Specify ingress path.                                                                                         | `/`                      |
| `ingress.hosts[0].paths[0].pathType`    | Specify path type.                                                                                            | `ImplementationSpecific` |
| `ingress.hosts[0].paths[0].serviceType` | Specify service type. It can be can be nemo or openai -- make sure your model serves the appropriate port(s). | `openai`                 |
| `ingress.tls`                           | Specify list of pairs of TLS secretName and hosts.                                                            | `[]`                     |

### Probe parameters

| Name                                 | Description                                                       | Value              |
| ------------------------------------ | ----------------------------------------------------------------- | ------------------ |
| `livenessProbe.enabled`              | Enable livenessProbe                                              | `true`             |
| `livenessProbe.method`               | LivenessProbe http or script, but no script is currently provided | `http`             |
| `livenessProbe.command`              | LivenessProbe script command to use (unsupported at this time)    | `["myscript.sh"]`  |
| `livenessProbe.path`                 | LivenessProbe endpoint path                                       | `/v1/health/live`  |
| `livenessProbe.initialDelaySeconds`  | Initial delay seconds for livenessProbe                           | `15`               |
| `livenessProbe.timeoutSeconds`       | Timeout seconds for livenessProbe                                 | `1`                |
| `livenessProbe.periodSeconds`        | Period seconds for livenessProbe                                  | `10`               |
| `livenessProbe.successThreshold`     | Success threshold for livenessProbe                               | `1`                |
| `livenessProbe.failureThreshold`     | Failure threshold for livenessProbe                               | `3`                |
| `readinessProbe.enabled`             | Enable readinessProbe                                             | `true`             |
| `readinessProbe.path`                | Readiness Endpoint Path                                           | `/v1/health/ready` |
| `readinessProbe.initialDelaySeconds` | Initial delay seconds for readinessProbe                          | `15`               |
| `readinessProbe.timeoutSeconds`      | Timeout seconds for readinessProbe                                | `1`                |
| `readinessProbe.periodSeconds`       | Period seconds for readinessProbe                                 | `10`               |
| `readinessProbe.successThreshold`    | Success threshold for readinessProbe                              | `1`                |
| `readinessProbe.failureThreshold`    | Failure threshold for readinessProbe                              | `3`                |
| `startupProbe.enabled`               | Enable startupProbe                                               | `true`             |
| `startupProbe.path`                  | StartupProbe Endpoint Path                                        | `/v1/health/ready` |
| `startupProbe.initialDelaySeconds`   | Initial delay seconds for startupProbe                            | `40`               |
| `startupProbe.timeoutSeconds`        | Timeout seconds for startupProbe                                  | `1`                |
| `startupProbe.periodSeconds`         | Period seconds for startupProbe                                   | `10`               |
| `startupProbe.successThreshold`      | Success threshold for startupProbe                                | `1`                |
| `startupProbe.failureThreshold`      | Failure threshold for startupProbe                                | `180`              |

### Metrics parameters

| Name                                      | Description                                                                                                      | Value   |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ------- |
| `metrics`                                 | Opens the metrics port for the triton inference server on port 8002.                                             |         |
| `metrics.enabled`                         | Enables metrics endpoint -- for legacyCompat only since current NIMs serve metrics on the OpenAI API port always | `true`  |
| `serviceMonitor`                          | Options for serviceMonitor to use the Prometheus Operator and the primary service object.                        |         |
| `metrics.serviceMonitor.enabled`          | Enables serviceMonitor creation.                                                                                 | `false` |
| `metrics.serviceMonitor.additionalLabels` | Specify additional labels for ServiceMonitor.                                                                    | `{}`    |

### Models parameters

| Name                 | Description                                                                                                                                                                                                                                                                | Value      |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------- |
| `model.nimCache`     | Path to mount writeable storage or pre-filled model cache for the NIM                                                                                                                                                                                                      | `""`       |
| `model.name`         | Specify name of the model in the API (name of the NIM). Mostly used for tests (optional otherwise). This must match the name from `/v1/models` to allow `helm test <release-name>` to work. In legacyCompat, this is required and sets the name of the model in /v1/models | `my-model` |
| `model.ngcAPISecret` | Name of pre-existing secret with a key named NGC_CLI_API_KEY that contains an API key for NGC model downloads                                                                                                                                                              | `""`       |
| `model.ngcAPIKey`    | NGC API key literal to use as the API secret and image pull secret when set                                                                                                                                                                                                | `""`       |
| `model.openaiPort`   | Specify Open AI Port.                                                                                                                                                                                                                                                      | `8000`     |
| `model.labels`       | Specify extra labels to be added on deployed pods.                                                                                                                                                                                                                         | `{}`       |
| `model.jsonLogging`  | Turn jsonl logging on or off. Defaults to true.                                                                                                                                                                                                                            | `true`     |
| `model.logLevel`     | Log level of NIM service. Possible values of the variable are TRACE, DEBUG, INFO, WARNING, ERROR, CRITICAL.                                                                                                                                                                | `INFO`     |

### Deprecated and Legacy Model parameters

| Name                   | Description                                                                                                                                         | Value         |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------- |
| `model.legacyCompat`   | Set `true` to enable compatiblity with pre-release NIM versions prior to 1.0.0.                                                                     | `false`       |
| `model.numGpus`        | (deprecated) Specify GPU requirements for the model.                                                                                                | `1`           |
| `model.subPath`        | (deprecated) Specify path within the model volume to mount if not the root -- default works with ngcInit and persistent volume. (legacyCompat only) | `model-store` |
| `model.modelStorePath` | (deprecated) Specify location of unpacked model.                                                                                                    | `""`          |

### Storage parameters

| Name                                                              | Description                                                                                                                                                                                                                       | Value                    |
| ----------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------ |
| `persistence`                                                     | Specify settings to modify the path `/model-store` if `model.legacyCompat` is enabled else `/.cache` volume where the model is served from.                                                                                       |                          |
| `persistence.enabled`                                             | Enable persistent volumes.                                                                                                                                                                                                        | `false`                  |
| `persistence.existingClaim`                                       | Secify existing claim. If using existingClaim, run only one replica or use a ReadWriteMany storage setup.                                                                                                                         | `""`                     |
| `persistence.storageClass`                                        | Specify persistent volume storage class. If set to "-", storageClassName: "", which disables dynamic provisioning. If undefined (the default) or set to null, no storageClassName spec is  set, choosing the default provisioner. | `""`                     |
| `persistence.accessMode`                                          | Specify accessModes. If using an NFS or similar setup, you can use ReadWriteMany.                                                                                                                                                 | `ReadWriteOnce`          |
| `persistence.stsPersistentVolumeClaimRetentionPolicy.whenDeleted` | Specify persistent volume claim retention policy when deleted. Only used with Stateful Set volume templates.                                                                                                                      | `Retain`                 |
| `persistence.stsPersistentVolumeClaimRetentionPolicy.whenScaled`  | Specifypersistent volume claim retention policy when scaled. Only used with Stateful Set volume templates.                                                                                                                        | `Retain`                 |
| `persistence.size`                                                | Specify size of claim (e.g. 8Gi).                                                                                                                                                                                                 | `50Gi`                   |
| `persistence.annotations`                                         | Specify annotations to be added to persistent volume.                                                                                                                                                                             | `{}`                     |
| `hostPath`                                                        | Configures model cache on local disk on the nodes using hostPath -- for special cases. One should investigate and understand the security implications before using this option.                                                  |                          |
| `hostPath.enabled`                                                | Enable hostPath.                                                                                                                                                                                                                  | `false`                  |
| `hostPath.path`                                                   | Specify path to the local model-store.                                                                                                                                                                                            | `/model-store`           |
| `nfs`                                                             | Configures model cache to sit on shared direct-mounted NFS. NOTE: you cannot set mount options using direct NFS mount to pods without a node-intalled nfsmount.conf. `csi-driver-nfs`` may be better in most cases.               |                          |
| `nfs.enabled`                                                     | Enable nfs mount                                                                                                                                                                                                                  | `false`                  |
| `nfs.path`                                                        | Specify path on NFS server to mount                                                                                                                                                                                               | `/exports`               |
| `nfs.server`                                                      | Specify NFS server address                                                                                                                                                                                                        | `nfs-server.example.com` |
| `nfs.readOnly`                                                    | Set to true to use readOnly                                                                                                                                                                                                       | `false`                  |

### Service parameters

| Name                  | Description                                            | Value       |
| --------------------- | ------------------------------------------------------ | ----------- |
| `service.type`        | Specify service type for the deployment.               | `ClusterIP` |
| `service.name`        | Override the default service name                      | `""`        |
| `service.openaiPort`  | Specify Open AI Port for the service.                  | `8000`      |
| `service.annotations` | Specify additional annotations to be added to service. | `{}`        |
| `service.labels`      | Specify additional labels to be added to service.      | `{}`        |
