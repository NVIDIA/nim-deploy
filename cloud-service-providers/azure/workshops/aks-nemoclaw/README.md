# AKS NemoClaw workshop

This workshop deploys **NemoClaw** on Azure Kubernetes Service (AKS) inside a **Docker-in-Docker (DinD)** pod. The workspace container builds sandboxes with Docker, proxies your in-cluster **Dynamo** frontend through `socat`, and configures NemoClaw to call **Azure OpenAI** (custom OpenAI-compatible endpoint).

## Prerequisites

- An AKS cluster with `kubectl` configured for it.
- **Azure Container Registry (ACR)** you can push to (same registry name you pass as `ACR_NAME`).
- **Docker** (local build uses `linux/amd64` for the image).
- **Azure CLI** (`az`), used for `az acr login` when push auth fails.
- A **Dynamo** deployment reachable from the pod (default in the manifest assumes a frontend service in the `dynamo` namespace). Adjust `DYNAMO_HOST` if your service name or namespace differs.
- A **LoadBalancer (or equivalent) Service** that exposes the NemoClaw HTTP / Control UI port to browsers. The pod manifest refers to a Service named `nemoclaw-http` in comments; create that Service (or rename labels/selectors consistently) so users open the UI at the same origin you set in `CHAT_UI_URL`.
- **Azure OpenAI**: a resource with a deployment, and an API key you are willing to store in a Kubernetes Secret locally (not committed).

## Layout

| Path | Role |
|------|------|
| `nemoclaw-base/` | Dockerfile and source baked into the `nemoclaw-dind-src` image. |
| `nemoclaw-install/nemoclaw-k8s.yaml` | Pod spec: placeholders for registry, UI URL, Azure endpoint, deployment name. |
| `nemoclaw-install/nemoclaw-secrets.example.yaml` | Template for the API key Secret. |
| `nemoclaw-install/nemoclaw-secrets.yaml` | **Local only** (gitignored): copy from the example and apply. |
| `install_k8s.sh` | Build image, push to ACR, apply Secret (if present), apply Pod manifest. |
| `dynamo/` | Optional Dynamo-related assets for the workshop (see files there). |

## Required settings

Edit **`nemoclaw-install/nemoclaw-k8s.yaml`** before or after the first apply (some values you only know after the LoadBalancer is provisioned).

| Setting | Where | What to put |
|--------|--------|-------------|
| Container image registry | `spec.containers[].image` (`workspace`) | Left as `YOUR_ACR_NAME.azurecr.io/...` in git. **`install_k8s.sh`** replaces `YOUR_ACR_NAME` with `ACR_NAME` when applying. |
| `CHAT_UI_URL` | env | **Exact origin** users type in the browser (scheme + host, no path, no trailing slash), e.g. `http://203.0.113.10` or `http://nemoclaw.example.com`. Must match how the LoadBalancer is reached; the gateway uses this for `allowedOrigins`. |
| `DYNAMO_HOST` | env | `host:port` for the Dynamo frontend **inside the cluster** (used by `socat`). Default: `vllm-disagg-frontend.dynamo.svc.cluster.local:8000` — change if your Service differs. |
| `NEMOCLAW_ENDPOINT_URL` | env | Azure OpenAI base URL with **`/openai/v1/`** suffix, e.g. `https://my-resource.openai.azure.com/openai/v1/`. |
| `NEMOCLAW_MODEL` | env | Your **Azure OpenAI deployment name** (not necessarily the same as the public model name). |
| Azure API key | Secret | See [Secrets](#secrets). Injected as `COMPATIBLE_API_KEY` via optional `secretKeyRef`; if the Secret is absent, the startup script defaults to `dummy` (fine only for endpoints that do not need a real key). |

Other env vars in the manifest (for example `NEMOCLAW_PROVIDER`, `NEMOCLAW_INFERENCE_API`, policy paths) are tuned for this workshop; change them only if you understand the NemoClaw installer behavior.

## Secrets

Do **not** commit API keys.

1. Copy the example file:

   ```bash
   cp nemoclaw-install/nemoclaw-secrets.example.yaml nemoclaw-install/nemoclaw-secrets.yaml
   ```

2. Replace `REPLACE_ME` under `azure-openai-api-key` with your Azure OpenAI key.

3. Ensure the Secret namespace and name match the Pod: `nemoclaw-workshop-credentials` in namespace `nemoclaw`.

`nemoclaw-secrets.yaml` is listed in `nemoclaw-install/.gitignore` so it stays local.

## Installation

1. **Create the namespace** (once):

   ```bash
   kubectl create namespace nemoclaw
   ```

2. **Configure** `nemoclaw-install/nemoclaw-k8s.yaml` (and create `nemoclaw-secrets.yaml` as above).

3. **Attach ACR to AKS** (or otherwise allow the cluster to pull from your registry), for example:

   ```bash
   az aks update -g YOUR_RG -n YOUR_AKS --attach-acr YOUR_ACR_NAME
   ```

4. From this directory (`aks-nemoclaw`), run the install script with your **short** ACR name (as in `az acr list`, not the full `*.azurecr.io` host):

   ```bash
   export ACR_NAME=yourregistry
   ./install_k8s.sh
   ```

   The script will:

   - Build `nemoclaw-base` as `yourregistry.azurecr.io/nemoclaw-dind-src:latest`.
   - Push to ACR (and run `az acr login --name "${ACR_NAME}"` if push fails for auth).
   - Apply `nemoclaw-install/nemoclaw-secrets.yaml` if that file exists.
   - Delete the existing `nemoclaw` pod (if any) and apply the pod manifest with the registry substitution.

5. **LoadBalancer and `CHAT_UI_URL`**: After the HTTP Service has an external IP or hostname, set `CHAT_UI_URL` to that origin, re-apply the manifest (or delete the pod so it is recreated with updated env), so the Control UI origin checks succeed.

## Manual apply (without the script)

If you build and push the image yourself, apply the Secret (if used) and the pod YAML, substituting the registry name in the image field to match your push target:

```bash
kubectl apply -f nemoclaw-install/nemoclaw-secrets.yaml -n nemoclaw   # if using secrets
sed "s|YOUR_ACR_NAME.azurecr.io|yourregistry.azurecr.io|g" nemoclaw-install/nemoclaw-k8s.yaml | kubectl apply -f - -n nemoclaw
```

## Dynamo

The `dynamo/` directory holds workshop-specific Dynamo material. Deploy and tune Dynamo for your cluster first, then align `DYNAMO_HOST` in `nemoclaw-k8s.yaml` with your frontend Service DNS name and port.
