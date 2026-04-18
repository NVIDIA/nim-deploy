# AKS NemoClaw workshop

This directory is an **Azure Kubernetes Service (AKS)–oriented workshop** for running **[NVIDIA NemoClaw](https://github.com/NVIDIA/NemoClaw)** on a cluster, optionally fronted by **NVIDIA Dynamo** serving **Nemotron-3 Super FP8** over SGLang in **disaggregated** mode.

## What this codebase does

- **`deploy_nemoclaw_k8s.sh`** — One entrypoint that can:
  1. Optionally deploy **Dynamo** from a Kubernetes manifest and wait until disaggregated tiers look healthy.
  2. **Clone** a pinned NemoClaw git tag into `nemoclaw-base/nemoclaw-src/NemoClaw` (for reproducible Docker build context).
  3. **Build** the `nemoclaw-base` image for `linux/amd64` (Node-based image with NemoClaw sources and workshop policy baked in).
  4. **Push** `nemoclaw-dind-src:latest` to your **Azure Container Registry (ACR)** (with `az acr login` retry on auth errors).
  5. **Apply** `nemoclaw-install` manifests: optional secrets, delete the `nemoclaw` pod, then `kubectl apply` `nemoclaw-k8s.yaml` with the registry host rewritten from your `--acr-name`.

- **`nemoclaw-base/`** — Dockerfile and build context: clones/copies **NemoClaw** at `NEMOCLAW_GIT_TAG` (default `v0.0.18`), copies **`nemoclaw-blueprint`** policy overrides, installs OpenShell, and produces the image referenced by the pod spec.

- **`nemoclaw-install/`** — Kubernetes manifests for a **Docker-in-Docker (DinD) + workspace** pod that runs NemoClaw’s installer non-interactively and wires **`NEMOCLAW_ENDPOINT_URL`** to an in-cluster Dynamo frontend (via `socat` and `host.openshell.internal`). Edit URLs, model name, and `CHAT_UI_URL` here for your environment.

- **`dynamo/`** — Vendored **Dynamo** tree (recipes, docs, tests). The deploy script’s default Dynamo manifest is  
  `dynamo/dynamo/recipes/nemotron-3-super-fp8/sglang/disagg/deploy.yaml`  
  (SGLang disaggregated Nemotron-3 Super FP8). See that recipe’s README for GPU and secret requirements.

## Prerequisites

- Shell with **bash**, **git**, **Docker**, **kubectl** (context pointing at your cluster), and **Azure CLI** (`az`) if you use ACR login from the script.
- **ACR** your cluster can pull from (attach ACR to AKS or use another supported pull pattern).
- Kubernetes **namespaces** you will use (defaults below); create them if they do not exist, for example:
  - `kubectl create namespace nemoclaw`
  - For Dynamo: `kubectl create namespace dynamo-system` (or your `--dynamo-namespace`).
- For **Dynamo** deployments: satisfy the recipe’s prerequisites (GPU node pool, Hugging Face token secret, model cache jobs, etc.) as described in `dynamo/dynamo/recipes/nemotron-3-super-fp8/README.md` and Dynamo’s Kubernetes docs under `dynamo/dynamo/docs/kubernetes/`.

## Install / refresh with `deploy_nemoclaw_k8s.sh`

Run the script from anywhere; it resolves paths relative to its own location.

### Required

| Flag / variable | Meaning |
|-----------------|--------|
| `--acr-name NAME` or `ACR_NAME` | **Short** ACR name only (e.g. `myregistry`), not the full `*.azurecr.io` login server. The image pushed is `NAME.azurecr.io/nemoclaw-dind-src:latest`. |

### Options (flags or environment variables)

| Flag | Env (if any) | Default | Purpose |
|------|----------------|---------|---------|
| `--install-dynamo` | — | off | Before build/push: `kubectl apply` the Dynamo manifest (see `DYNAMO_DEPLOY_MANIFEST`), then **wait** until every pod in the Dynamo namespace is Running with full readiness, and there are at least **`DYNAMO_DISAGG_MIN_PODS`** ready pods per disagg tier (names matching `-disagg-decode-`, `-disagg-frontend-`, `-disagg-prefill-`). |
| `--nemoclaw-namespace NS` | `NEMOCLAW_NAMESPACE` | `nemoclaw` | Namespace for NemoClaw `kubectl apply` / pod delete. |
| `--dynamo-namespace NS` | `DYNAMO_NAMESPACE` | `dynamo-system` | Namespace used when `--install-dynamo` is set. |
| `-h`, `--help` | — | — | Print usage and exit. |

### Environment-only tuning

| Variable | Default | Purpose |
|----------|---------|---------|
| `DYNAMO_DEPLOY_MANIFEST` | `dynamo/dynamo/recipes/nemotron-3-super-fp8/sglang/disagg/deploy.yaml` (under this workshop) | Manifest path for `--install-dynamo`. |
| `DYNAMO_READY_POLL_INTERVAL` | `15` | Seconds between pod status polls while waiting. |
| `DYNAMO_READY_TIMEOUT_SEC` | `3600` | Max wait seconds (`0` = no limit). |
| `DYNAMO_DISAGG_MIN_PODS` | `3` | Minimum **ready** pods per decode / frontend / prefill tier (name substring match). |
| `NEMOCLAW_GIT_URL` | `https://github.com/NVIDIA/NemoClaw.git` | Clone URL for NemoClaw under `nemoclaw-base/nemoclaw-src/NemoClaw`. |
| `NEMOCLAW_GIT_TAG` | `v0.0.18` | Git **tag** to fetch (detached checkout). If unset, `NEMOCLAW_GIT_REF` is still read for backward compatibility. |
| `VERBOSE` | `0` | Set to `1` for more detailed logs (e.g. push output, Dynamo criteria). |

### Example commands

**NemoClaw only** (build, push, refresh pod; assumes Dynamo is already installed if the pod expects it):

```bash
./deploy_nemoclaw_k8s.sh --acr-name myregistry
```

**Dynamo + NemoClaw** (apply default SGLang disagg recipe, wait for pods, then build/push/refresh):

```bash
./deploy_nemoclaw_k8s.sh --acr-name myregistry --install-dynamo
```

**Custom namespaces**:

```bash
./deploy_nemoclaw_k8s.sh \
  --acr-name myregistry \
  --install-dynamo \
  --dynamo-namespace my-dynamo \
  --nemoclaw-namespace my-nemoclaw
```

**Custom Dynamo manifest** (same flags; override path):

```bash
export DYNAMO_DEPLOY_MANIFEST="/path/to/your/deploy.yaml"
./deploy_nemoclaw_k8s.sh --acr-name myregistry --install-dynamo
```

### After the script

1. **`nemoclaw-install/nemoclaw-k8s.yaml`** — Adjust `CHAT_UI_URL` (must match the origin users type in the browser for the Control UI), `DYNAMO_HOST` / service DNS if your frontend differs, `NEMOCLAW_ENDPOINT_URL`, and `NEMOCLAW_MODEL` as needed, then re-run the script or `kubectl apply` the same pattern the script uses.
2. **Secrets** — Copy `nemoclaw-install/nemoclaw-secrets.example.yaml` to `nemoclaw-secrets.yaml` (gitignored), fill Azure OpenAI / NGC keys if you use those paths, and ensure the pod env references match. The script applies `nemoclaw-secrets.yaml` when the file exists.

## Related paths

- Default Dynamo recipe: `dynamo/dynamo/recipes/nemotron-3-super-fp8/sglang/disagg/`
- Pod and Service definitions: `nemoclaw-install/nemoclaw-k8s.yaml`
