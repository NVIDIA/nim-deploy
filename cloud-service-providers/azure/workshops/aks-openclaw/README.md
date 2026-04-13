# AKS OpenClaw + Microsoft Foundry

This workshop folder contains Kubernetes manifests and a small container entrypoint helper used to run **[OpenClaw](https://github.com/openclaw/openclaw)** on **Azure Kubernetes Service (AKS)** with the gateway wired to **Microsoft Foundry** (Azure AI Foundry) as the model provider.

In plain terms: you get a single **OpenClaw gateway pod** on your cluster that serves the Control UI and agent traffic on **port 18789**, while LLM calls go to your **Foundry project endpoint** using the correct Azure **Responses** API shape (`azure-openai-responses`), not the generic OpenAI Responses mode that Azure often rejects.

---

## What this codebase does

### Components

| Artifact | Role |
|----------|------|
| [`openclaw-k8s.yaml`](./openclaw-k8s.yaml) | Core stack: `ConfigMap` (`openclaw.json`), `ConfigMap` (`openclaw-foundry-endpoint` → `OPENCLAW_FOUNDRY_BASE_URL`), `Secret` (credentials), `Pod` (`openclaw`), `ClusterIP` `Service` on 18789. |
| [`openclaw-ingress.yaml`](./openclaw-ingress.yaml) | Optional **`LoadBalancer`** `Service` (`openclaw-http`) mapping **80 → 18789** for a public Azure LB in front of the same pod selector. |
| [`docker-entrypoint.sh`](./docker-entrypoint.sh) | Optional wrapper used when building a custom image: runs `openclaw doctor --fix`, optionally skips onboard when `OPENCLAW_SKIP_ONBOARD=1`, and passes **`--port`** / **`--token`** to `openclaw gateway run` when env vars are set. The manifest in this folder uses the upstream **`ghcr.io/openclaw/openclaw`** image; wire this script in your own `Dockerfile` if you need the same behavior in a custom build. |

### Runtime flow

1. **Init container** (`busybox`) copies `openclaw.json` from the `ConfigMap` into an **`emptyDir`** mounted at `/home/node/.openclaw`. This avoids mounting the ConfigMap file directly as `subPath`, which can block OpenClaw from renaming/updating its config (EBUSY on some setups).

2. **Main container** runs OpenClaw with:
   - **`OPENCLAW_SKIP_ONBOARD=1`** so the gateway starts from the pre-provisioned config instead of interactive `openclaw onboard` / `openclaw setup`.
   - **`OPENCLAW_CONFIG_PATH=/home/node/.openclaw/openclaw.json`** pointing at the copied file.
   - **`OPENCLAW_GATEWAY_BIND=lan`** (and `gateway.bind: "lan"` in JSON) so the process listens on **0.0.0.0**. If it bound only to loopback, **Kubernetes Services and LoadBalancers would see connection refused** from kube-proxy.

3. **Microsoft Foundry** is configured under `models.providers.microsoft-foundry` in `openclaw.json`:
   - **`baseUrl`** comes from env **`OPENCLAW_FOUNDRY_BASE_URL`**, injected from the **`openclaw-foundry-endpoint`** `ConfigMap` (set your resource and project names there, or override the map with `kubectl create configmap … --from-literal=…`).
   - **`api`: `azure-openai-responses`** — required for Azure; generic `openai-responses` can produce payloads Azure rejects (400 schema / empty item type). Use a **recent OpenClaw** (e.g. **2026.4.x** as noted in the manifest comments).
   - **`apiKey`** / headers use **`OPENCLAW_MODEL_API_KEY`** from the `Secret`.
   - Default agent model is **`OPENCLAW_AGENT_PRIMARY_MODEL`**, e.g. `microsoft-foundry/gpt-5.3-chat`, aligned with the provider block and `agents.defaults.models`.

4. **Gateway auth**: `gateway.auth.token` is expanded from **`OPENCLAW_GATEWAY_TOKEN`** in the `Secret`. The Control UI must use the **same** token (or a URL with `?token=...`). If the token is missing or mismatched, you will see **`token_missing` / `token_mismatch`** in logs. Prefer generating a stable random value (e.g. `openssl rand -hex 32`) and storing it only in the Secret (or creating the Secret out-of-band and **removing** inline `Secret` from YAML before commit).

5. **Control UI over HTTP**: the sample `openclaw.json` sets `controlUi.allowInsecureAuth`, `dangerouslyDisableDeviceAuth`, and permissive `allowedOrigins` for **plain HTTP** (e.g. public LB without TLS). **This is appropriate for workshops only.** For production, terminate **TLS** (Ingress, Application Gateway, etc.) and set **`allowedOrigins`** to your real **`https://`** origin instead.

### Namespace

All resources use the **`nemoclaw`** namespace so **Pod labels**, **Services**, and **Endpoints** stay consistent. If the pod and Service are in different namespaces, a LoadBalancer can show **no endpoints** even when the pod is running.

---

## Prerequisites

- An **AKS** cluster (or any Kubernetes cluster on Azure with working `LoadBalancer` if you use `openclaw-ingress.yaml`).
- **`kubectl`** configured to the correct context.
- **Network** from the cluster to your Foundry endpoint (`*.services.ai.azure.com` or your configured host).
- **OpenClaw image**: default is `ghcr.io/openclaw/openclaw` with `imagePullPolicy: IfNotPresent`. For reproducible workshops, pin a tag (e.g. `2026.4.8`) in the `Pod` spec after you validate it.
- **Foundry**: a project with a deployed model whose **id** matches the manifest (e.g. `gpt-5.3-chat`) or change the manifest to your model id and `OPENCLAW_AGENT_PRIMARY_MODEL` accordingly.

---

## One-time setup

### 1. Namespace

```bash
kubectl create namespace nemoclaw --dry-run=client -o yaml | kubectl apply -f -
```

### 2. Secrets (recommended: out-of-band)

Avoid re-applying placeholder secrets from Git. Create the Secret once:

```bash
GW=$(openssl rand -hex 32)
kubectl create secret generic openclaw-credentials -n nemoclaw \
  --from-literal=OPENCLAW_MODEL_API_KEY='YOUR_FOUNDRY_KEY' \
  --from-literal=OPENCLAW_GATEWAY_TOKEN="$GW"
```

If the Secret already exists:

```bash
kubectl delete secret openclaw-credentials -n nemoclaw --ignore-not-found
# then re-run create secret as above
```

**Before** applying [`openclaw-k8s.yaml`](./openclaw-k8s.yaml), either:

- Remove the `Secret` object from the file and keep only `ConfigMap` + `Pod` + `Service`, **or**
- Replace placeholders with real values and **never commit** real keys.

### 3. Foundry endpoint (`OPENCLAW_FOUNDRY_BASE_URL`)

The pod reads **`OPENCLAW_FOUNDRY_BASE_URL`** from the **`openclaw-foundry-endpoint`** `ConfigMap` (same value is referenced in `openclaw.json` as `${OPENCLAW_FOUNDRY_BASE_URL}`).

**Option A — edit YAML:** In [`openclaw-k8s.yaml`](./openclaw-k8s.yaml), find `kind: ConfigMap` / `name: openclaw-foundry-endpoint` and replace `YOUR_FOUNDRY_RESOURCE_NAME` and `YOUR_FOUNDRY_PROJECT_NAME` in the URL.

**Option B — CLI (good for CI):**

```bash
kubectl create configmap openclaw-foundry-endpoint -n nemoclaw --dry-run=client -o yaml \
  --from-literal=OPENCLAW_FOUNDRY_BASE_URL='https://<resource>.services.ai.azure.com/api/projects/<project>/openai/v1' \
  | kubectl apply -f -
```

### 4. Agent primary model

In the **`Pod`** env, **`OPENCLAW_AGENT_PRIMARY_MODEL`** must stay `microsoft-foundry/<modelId>` where `<modelId>` matches `models[].id` under `microsoft-foundry` in the `openclaw-config` `openclaw.json`. If you change the model id, update both the env var and the `ConfigMap` JSON (`agents.defaults.models` keys must stay aligned).

---

## Deploy / run

From this directory (`aks-openclaw`), after secrets and env edits are correct:

### Apply core manifest (ConfigMap, Pod, Service)

```bash
kubectl delete pod openclaw -n nemoclaw --ignore-not-found && kubectl apply -f ./openclaw-k8s.yaml -n nemoclaw
```

Notes:

- Resources in the YAML already declare **`metadata.namespace: nemoclaw`**. The **`-n nemoclaw`** flag is harmless and matches the workshop convention; it also sets the default namespace for any future objects you add without an explicit namespace.
- Deleting the **Pod** forces a fresh pod (new `emptyDir`, re-run init container) while leaving the Service and ConfigMap in place.

### Optional public LoadBalancer (HTTP)

After the pod is ready:

```bash
kubectl apply -f ./openclaw-ingress.yaml -n nemoclaw
```

Check that endpoints are populated:

```bash
kubectl get endpoints openclaw-http -n nemoclaw -o wide
kubectl get pods -n nemoclaw -l app=openclaw
```

If **Endpoints** are empty, verify **namespace**, **`app: openclaw`** labels, and **`OPENCLAW_GATEWAY_BIND=lan`**.

### Tear down (optional)

```bash
kubectl delete -f ./openclaw-ingress.yaml -n nemoclaw --ignore-not-found
kubectl delete -f ./openclaw-k8s.yaml -n nemoclaw --ignore-not-found
kubectl delete secret openclaw-credentials -n nemoclaw --ignore-not-found
```

---

## Access

### Port-forward (simplest)

```bash
kubectl port-forward pod/openclaw 18789:18789 -n nemoclaw
```

Then open the Control UI / gateway at **`http://127.0.0.1:18789`** (exact path depends on OpenClaw version).

### LoadBalancer service

After `openclaw-ingress.yaml`:

```bash
kubectl get svc openclaw-http -n nemoclaw
```

Use the **EXTERNAL-IP** on port **80** (mapped to gateway **18789**).

If you use the dashboard without `?token=...`, paste the same **`OPENCLAW_GATEWAY_TOKEN`** you stored in the Secret into Control UI settings.

---

## Custom image (optional)

If you build an image that uses [`docker-entrypoint.sh`](./docker-entrypoint.sh), ensure the image **`ENTRYPOINT`** invokes this script before `openclaw gateway run`, and set the same env vars as in the `Pod` spec. The workshop manifest does **not** require a custom image unless you want this entrypoint behavior in the published image itself.

Example build/push (adjust registry/tag):

```bash
docker build -t <registry>/openclaw:2026.4.8 .
docker push <registry>/openclaw:2026.4.8
```

Then set `spec.containers[0].image` in [`openclaw-k8s.yaml`](./openclaw-k8s.yaml) to your image.

---

## Troubleshooting

| Symptom | Things to check |
|--------|------------------|
| **401** from provider | Foundry key in **`OPENCLAW_MODEL_API_KEY`**, and **`OPENCLAW_AGENT_PRIMARY_MODEL`** uses **`microsoft-foundry/...`**, not `default/...`. |
| **400** / schema errors from Azure | Confirm **`api`: `azure-openai-responses`** in the provider block; upgrade OpenClaw if needed. |
| **LoadBalancer has no endpoints** | Pod in **`nemoclaw`**, label **`app: openclaw`**, gateway **`bind`** / **`OPENCLAW_GATEWAY_BIND`** is **`lan`**. |
| **`token_missing` / `token_mismatch`** | Stable **`OPENCLAW_GATEWAY_TOKEN`** in Secret matches UI / URL token; avoid letting OpenClaw auto-generate a different token on disk. |
| **Config / rename errors** | Init container + **`emptyDir`** pattern must stay; do not mount ConfigMap `subPath` directly onto the live config path OpenClaw mutates. |

---

## Security reminder

Treat **`OPENCLAW_MODEL_API_KEY`** and **`OPENCLAW_GATEWAY_TOKEN`** as secrets. Prefer **`kubectl create secret`** or a secret manager integration, and **rotate** keys that may have been committed or shared.
