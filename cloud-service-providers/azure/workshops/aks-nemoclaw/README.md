# Enterprise agents on Azure Kubernetes Service

This workshop shows [NVIDIA NemoClaw](https://github.com/NVIDIA/NemoClaw) agents talking to [NVIDIA Dynamo](https://github.com/ai-dynamo/dynamo) inference on AKS. The sample model is the Nemotron-3 Super FP8 weights listed below.

## Document purpose

This README explains **why** the workshop exists and **how** to run it. The sample model ID is `nvidia/NVIDIA-Nemotron-3-Super-120B-A12B-FP8`. Use `deploy_nemoclaw_k8s.sh` to optionally install inference, build and push a container to Azure Container Registry (ACR), and update the Kubernetes pod.

## Value in short

Agents send a lot of traffic to the model: long prompts, tools, search hits, and streamed answers. You need two things working together:

1. A **governable application surface** — rules, users, tools, and logs live here.
2. An **inference plane** — the model runs here, on your GPUs, with stable cost and latency inside your cloud boundary.

### Governable application surface

This is the software layer where **your** rules apply (not only inside the model file).

- **Who** — which users or services may run an agent, and with what access.
- **What** — which tools, APIs, and data the agent may use; what may go into the prompt.
- **How** — how text is filtered, redacted, logged, and kept for audit; how a request is traced from the user through tools to the model call.

You change these with config and policy; you do not need to retrain the model. Here, **NemoClaw** plays this role: assistants, sandboxes, and policies sit **above** the plain HTTP call to the model.

### Inference plane

This is the stack that **runs** the model: GPUs, scheduling, and the HTTP API your apps call. Some people say “inference plan” for the same idea (how you buy and use GPU capacity).

- **What** — which model, precision (e.g. FP8), max context, and API shape (here: OpenAI-style routes); how traffic is split between workers.
- **Where** — which AKS cluster, GPU nodes, and region run the job and hold weights/cache.
- **How** — how requests wait in line, batch, scale up and down, and how you watch errors and usage for ops and finance.

Here, **Dynamo on AKS** is the inference plane. The governable surface **sends** requests in; the plane **returns** answers and metrics for logging and policy, without every user dealing with cluster details.

### How the two layers connect

The **governable surface** is close to **people and rules**. The **inference plane** is close to **GPUs and speed**. They meet at one API: the surface checks and shapes requests; the plane runs them inside your tenant.

```mermaid
flowchart TB
  subgraph GAS["Governable application surface"]
    direction TB
    WHO["Who may act"]
    SCOPE["What may be touched"]
    PROC["How we log and limit"]
  end
  subgraph IP["Inference plane"]
    direction TB
    MODEL["What model and API"]
    PLACE["Where GPUs run"]
    SERVE["How we serve and scale"]
  end
  U[Users and systems] --> GAS
  GAS -->|"OK requests,<br/>trimmed context"| IP
  IP -->|"Answers, token counts,<br/>errors, timing"| GAS
  IP --> HW[GPUs and cluster]
```

### Three workshop layers

1. **Agents (NemoClaw)** — Assistants, policies, sandboxes. Turns real work into model calls you can watch and control.
2. **Serving (Dynamo)** — OpenAI-style HTTP front door, routing, GPU workers on Kubernetes. Many apps can share one stack.
3. **Model (Nemotron FP8)** — Large hybrid model (attention + recurrence + experts) in FP8 where it helps. Uses less GPU memory than BF16-only for the same class of model, so you can often get **more tokens per GPU dollar** when the model fits the task.

Together: agent load + shared serving + one strong NVIDIA model on AKS.

## Azure AKS and the two layers

AKS is not “just Kubernetes”: Azure adds identity, storage, networking, and policy hooks. Those hooks line up differently with the **governable application surface** than with the **inference plane**.

**Governable surface (who / what / how).** You care who can deploy or change agent policy, where secrets live, and whether traffic and logs stay inside your boundary. On AKS that often means **Microsoft Entra ID** (Azure RBAC on the control plane and Kubernetes RBAC in the cluster) so only the right teams touch NemoClaw config or secrets. **Azure Key Vault** with the **Secrets Store CSI driver** (or workload identity to Key Vault) keeps API keys, NGC keys, and Hugging Face tokens out of plain YAML in Git. **Azure Policy** and **Defender for Cloud** add org-wide rules (for example: no public Services where policy forbids them). **Private AKS** or **internal load balancers** reduce exposure of the control plane or admin paths. **Azure Monitor** and **Container Insights** give one place to retain and query audit-style logs if your compliance team requires it. **Network policies** (with **Azure CNI**) can separate namespaces so agent pods and inference pods talk only on allowed ports.

**Inference plane (model / GPUs / scale).** Here you care about GPU SKUs, disk speed for weights, and scale. AKS **GPU node pools** (for example NC/ND families) host Dynamo workers. **Availability zones** on node pools improve uptime when a zone has an issue. **Cluster autoscaler** and **Horizontal Pod Autoscaler** (or KEDA) grow or shrink capacity with queue depth. **Azure managed disks** (often **Premium SSD**) back the **PVC** that holds the large Nemotron download so workers start faster and keep steady I/O. **Azure Container Registry** plus **managed identity** (or ACR attach) avoids long-lived docker passwords on nodes. **Standard Load Balancer** or **Application Gateway** exposes the front end your users or NemoClaw hit, optionally **internal** only so the model API never leaves the VNet.

Neither layer replaces the other: Azure gives guardrails and plumbing; NemoClaw and Dynamo still implement the actual agent rules and model serving.

```mermaid
flowchart TB
  subgraph Gas["Governable surface — typical Azure hooks"]
    RBAC["Entra ID + RBAC<br/>who edits agents / secrets"]
    KV["Key Vault + CSI / workload ID<br/>keys not in git"]
    POL["Azure Policy / Defender<br/>org guardrails"]
    NP["Network policies + CNI<br/>pod-to-pod rules"]
    LOG["Azure Monitor / Insights<br/>logs and alerts"]
  end
  subgraph Ip["Inference plane — typical Azure hooks"]
    GPU["GPU node pools + zones<br/>where models run"]
    PVC["Managed disk / Files PVC<br/>model cache"]
    SCALE["Cluster + HPA / KEDA<br/>scale with load"]
    ACR["ACR + managed identity<br/>pull images"]
    LB["Load balancer / ingress<br/>front door"]
  end
```

```mermaid
flowchart LR
  subgraph Sub["Your Azure subscription"]
    U[Users / operators]
    U --> EID[Entra ID]
    EID --> ING[Ingress or LB]
    ING --> NC[NemoClaw<br/>governable surface]
    NC -->|cluster DNS / private link| FE[Dynamo frontend<br/>inference plane]
    FE --> WRK[GPU workers]
    WRK --> VOL[(PVC on Azure Disk)]
  end
```

## Why disaggregated serving helps here

Big models often split **prefill** (new prompt work) and **decode** (next tokens). Workers pass cache/state between them. Dynamo does that in **disaggregated** mode: prefill workers take new context, decode workers keep generating, the front end sends work to both. This repo’s default uses **SGLang** and **NIXL** between workers; see `dynamo/dynamo/recipes/nemotron-3-super-fp8/sglang/disagg/deploy.yaml`.

NemoClaw drives **realistic** traffic (chat, tools, install steps), not a single lab query.

## Money, data, and “your own” inference

**Metered APIs** (e.g. OpenAI, Anthropic): you pay per token; the bill grows with use.

**Your own inference** (Dynamo on your AKS): you pay for GPUs and ops; tokens can get **cheaper per unit** as you use the hardware more.

Some people call your stack a **token factory**: answers are made **inside** your cloud under **your** rules, not only bought as an outside line item.

Using Dynamo on AKS ties more of your agent spend to capacity you already run. You can still send some traffic to outside APIs when policy allows.

| Topic | Metered API | Dynamo on your AKS |
|--------|-------------|-------------------|
| Cost vs use | Bill grows with adoption | Fixed/step GPU cost; busy GPUs lower cost per token |
| Data | Leaves your account unless contracts say otherwise | Prompts and answers stay in your subscription unless you send them out |
| Busy times | Shared public service may queue | You size your cluster to your SLA |
| Reuse | Fast access to many public models | One stack many apps can share (OpenAI-style clients) |

```mermaid
flowchart TB
  subgraph Demand["Your org"]
    U[Users]
    AP[Agent platform]
    U --> AP
  end
  subgraph Own["Your inference"]
    FE[Dynamo front end]
    W[GPU workers]
    FE --> W
  end
  subgraph Buy["Paid APIs"]
    API[Third-party models]
  end
  AP -->|"most traffic"| FE
  AP -.->|"sometimes"| API
```

### Token volume

Agents burn many tokens per task: system text, search, tool JSON, plans, UI stream. Across a company, small per-user use adds up fast—often more than a pilot guessed.

```mermaid
xychart-beta
    title "Example only: token volume vs rollout size"
    x-axis [Pilot, One unit, Many units, Whole company]
    y-axis "Relative volume" 0 --> 100
    line [5, 25, 55, 100]
```

Real curves depend on user count, agent depth, and max context. Plan for **cost per token** and **serving speed**, not only model quality.

### Cost per token (simple view)

**Cost per token ≈ (all-in cost for a month) ÷ (tokens served that month).**

Dynamo helps the bottom number (more tokens per GPU) and ties the top number to **GPUs you control**, not a retail API markup.

```mermaid
pie title Example only: mix after partial move to own GPUs
    "Your GPUs" : 72
    "Paid APIs" : 28
```

### Strategy chart (example only)

```mermaid
quadrantChart
    title Example only — not advice
    x-axis You run less infra --> You run more infra
    y-axis Hard to predict cost --> Easier to predict cost
    quadrant-1 Strong for steady scale
    quadrant-2 More ops, messy spend
    quadrant-3 Try and learn
    quadrant-4 Less ops, messy spend
    Paid APIs: [0.28, 0.32]
    Dynamo on AKS: [0.74, 0.76]
```

Savings are **not** automatic. You still need busy GPUs, a full cost picture (hardware, power, staff, licenses, risk), and the right model. Nemotron here is **one** choice.

## Disaggregated serving (Dynamo)

**Prefill** workers handle new input (attention and, for hybrid models, extra state). **Decode** workers keep making tokens. They share state over the network (this workshop: **SGLang** + **NIXL**). A **frontend** takes client requests and talks to both tiers.

```mermaid
flowchart LR
  subgraph Consumers
    CL[Agents and users]
  end
  subgraph Dyn["Dynamo on Kubernetes"]
    FE[Frontend]
    PF[Prefill workers]
    DC[Decode workers]
  end
  CL -->|asks| FE
  FE -->|prefill| PF
  PF -->|state transfer| DC
  FE -->|decode| DC
  DC -->|answer| FE
  FE -->|answer| CL
```

**Tradeoff:** more moving parts than one big pool; you must run more pod types and tune the network/GPU layout.

## KV routing and this workshop’s model

Dynamo can **route** requests to workers that already hold part of the prompt in cache (fewer repeats, faster first token). See `dynamo/dynamo/docs/components/router/router-concepts.md` and `router-guide.md` in the bundled Dynamo tree.

For **this** Nemotron hybrid recipe, the bundled **disagg** setup does **not** use full KV-overlap routing like simple attention-only stacks. Hybrid Mamba + attention models do not yet give clean KV “events” for exact routing in these backends. This workshop’s SGLang disagg file uses **round-robin** and turns KV events **off**. That may change in future releases.

## What this repo does

On AKS: agents in Kubernetes; inference installed by the script or by you; default recipe is **SGLang disagg** for the model ID at the top.

- **`deploy_nemoclaw_k8s.sh`**
  1. Optionally install Dynamo from a manifest and wait until pods look ready.
  2. Clone a fixed NemoClaw git tag into `nemoclaw-base/nemoclaw-src/NemoClaw`.
  3. Build `nemoclaw-base` for `linux/amd64`.
  4. Push `nemoclaw-dind-src:latest` to ACR (`az acr login` retry on auth errors).
  5. Apply `nemoclaw-install` (secrets if present, delete `nemoclaw` pod, apply `nemoclaw-k8s.yaml` with your registry name).

- **`nemoclaw-base/`** — Docker build: NemoClaw at `NEMOCLAW_GIT_TAG` (default `v0.0.18`), `nemoclaw-blueprint`, OpenShell; image the pod uses.

- **`nemoclaw-install/`** — YAML for a DinD + workspace pod: non-interactive NemoClaw install; `NEMOCLAW_ENDPOINT_URL` points at Dynamo in the cluster (`socat`, `host.openshell.internal`). Edit URLs and `CHAT_UI_URL` for your site.

- **`dynamo/`** — Copy of Dynamo (recipes, docs, tests). See [Nemotron-3 Super FP8 Dynamo recipes](#nemotron-3-super-fp8-dynamo-recipes) below.

## Nemotron-3 Super FP8 Dynamo recipes

Upstream NVIDIA maintains several ready-made layouts for `nvidia/NVIDIA-Nemotron-3-Super-120B-A12B-FP8` in the open Dynamo repo:

- Recipe folder: [github.com/ai-dynamo/dynamo/tree/main/recipes/nemotron-3-super-fp8](https://github.com/ai-dynamo/dynamo/tree/main/recipes/nemotron-3-super-fp8)
- Full prerequisites and quick start: [github.com/ai-dynamo/dynamo/blob/main/recipes/nemotron-3-super-fp8/README.md](https://github.com/ai-dynamo/dynamo/blob/main/recipes/nemotron-3-super-fp8/README.md)

**Other layouts (not only disagg).** The same README lists **aggregated** and **disaggregated** options, for example:

| Path under `recipes/nemotron-3-super-fp8/` | Mode | Backend | Notes (from upstream) |
|--------------------------------------------|------|---------|------------------------|
| `vllm/agg/` | Aggregated | vLLM | 4× H100/H200, TP=4 |
| `sglang/agg/` | Aggregated | SGLang | 4× H100/H200, TP=4 |
| `trtllm/disagg/` | Disaggregated | TensorRT-LLM | TP=2 prefill/decode split, UCX transfer |
| `sglang/disagg/` | Disaggregated | SGLang | TP=2 split, nixl (or mooncake) transfer |

This workshop’s `deploy_nemoclaw_k8s.sh` default is the **SGLang disaggregated** manifest only. You can point `DYNAMO_DEPLOY_MANIFEST` at another `deploy.yaml` if your cluster and ops model fit a different row.

**Example manifest (copy in this repo).** The vendored path matches the upstream `sglang/disagg/deploy.yaml` layout; it declares a `DynamoGraphDeployment` and expects a shared **model-cache** PVC (`create: false` in the snippet—so you create/cache the model on a PVC first). Opening lines:

```1:35:dynamo/dynamo/recipes/nemotron-3-super-fp8/sglang/disagg/deploy.yaml
# SPDX-FileCopyrightText: Copyright (c) 2025-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# Disaggregated SGLang deployment: prefill/decode split with nixl KV transfer.
# Tested with dynamo 1.0 (SGLang 0.5.9).
#
# Uses TP=2 per worker (prefill: 2 GPUs, decode: 2 GPUs) for a total of 4 GPUs.
# KV cache is transferred between workers via nixl (GPU-direct).
#
# NOT working on dynamo 0.9.1 — same blocking bugs as sglang/agg.
#
# Known issue: Prefill warmup logs a non-blocking warning:
#   "Prefill warmup failed: 'SamplingParams' object is not subscriptable"
# This does not affect functionality.
#
apiVersion: nvidia.com/v1alpha1
kind: DynamoGraphDeployment
metadata:
  name: nemotron-super-fp8-sglang-disagg
spec:
  backendFramework: sglang
  envs:
    - name: HF_HOME
      value: /opt/models
  pvcs:
    - name: model-cache
      create: false
  services:
    Frontend:
      componentType: frontend
      replicas: 1
      volumeMounts:
        - name: model-cache
          mountPoint: /opt/models
      extraPodSpec:
```

**Preliminaries from the upstream README (do these before or with the deploy).** In short:

1. **Dynamo on the cluster** — Install the Dynamo platform as in the [Kubernetes deployment guide](https://github.com/ai-dynamo/dynamo/blob/main/docs/kubernetes/README.md) (linked from the recipe README).
2. **GPUs** — Recipe table targets **4× H100 80GB or H200** for these Nemotron layouts.
3. **Hugging Face secret** — `kubectl create secret generic hf-token-secret --from-literal=HF_TOKEN="…" -n <namespace>` with a token that can access the NVIDIA model.
4. **Model cache and PVC** — Under `recipes/nemotron-3-super-fp8/model-cache/`, apply the manifests so weights land on a **persistent volume**; set **`storageClassName`** in `model-cache/model-cache.yaml` to a class your cluster provides, then run the download **Job** and wait until it completes (`kubectl wait --for=condition=Complete job/model-download …`). The README notes a **~240 GB** download and roughly **30–60 minutes** depending on bandwidth.
5. **Then deploy** — `kubectl apply -f <chosen>/deploy.yaml -n <namespace>` (e.g. `sglang/disagg` or an **agg** path above).

The copy under `dynamo/dynamo/recipes/nemotron-3-super-fp8/` in this workshop should match upstream for the same paths; when in doubt, compare with [the tree on GitHub](https://github.com/ai-dynamo/dynamo/tree/main/recipes/nemotron-3-super-fp8).

## Prerequisites

- `bash`, `git`, Docker, `kubectl` (pointed at your cluster), `az` if you use ACR login from the script.
- An ACR your cluster can pull from.
- Namespaces if missing, e.g. `kubectl create namespace nemoclaw` and `kubectl create namespace dynamo-system` (or your chosen names).
- For Dynamo + Nemotron: complete the [preliminaries above](#nemotron-3-super-fp8-dynamo-recipes) and read the local copy at `dynamo/dynamo/recipes/nemotron-3-super-fp8/README.md` plus `dynamo/dynamo/docs/kubernetes/` for platform install details.

## `deploy_nemoclaw_k8s.sh`

Run from any directory; the script finds its own files.

### Required

| Flag / variable | Meaning |
|-----------------|--------|
| `--acr-name NAME` or `ACR_NAME` | Short ACR name only (e.g. `myregistry`). Image: `NAME.azurecr.io/nemoclaw-dind-src:latest`. |

### Options

| Flag | Env | Default | Purpose |
|------|-----|---------|---------|
| `--install-dynamo` | — | off | Apply Dynamo YAML, wait for Running/Ready pods and enough ready pods per disagg tier (`-disagg-decode-`, `-disagg-frontend-`, `-disagg-prefill-`). |
| `--nemoclaw-namespace NS` | `NEMOCLAW_NAMESPACE` | `nemoclaw` | Where NemoClaw YAML applies. |
| `--dynamo-namespace NS` | `DYNAMO_NAMESPACE` | `dynamo-system` | Where Dynamo YAML applies when using `--install-dynamo`. |
| `-h`, `--help` | — | — | Help text. |

### Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `DYNAMO_DEPLOY_MANIFEST` | `dynamo/dynamo/recipes/nemotron-3-super-fp8/sglang/disagg/deploy.yaml` | YAML for `--install-dynamo`. |
| `DYNAMO_READY_POLL_INTERVAL` | `15` | Seconds between pod checks. |
| `DYNAMO_READY_TIMEOUT_SEC` | `3600` | Max wait (`0` = no limit). |
| `DYNAMO_DISAGG_MIN_PODS` | `3` | Min ready pods per decode / front / prefill tier (name match). |
| `NEMOCLAW_GIT_URL` | `https://github.com/NVIDIA/NemoClaw.git` | Git remote for NemoClaw. |
| `NEMOCLAW_GIT_TAG` | `v0.0.18` | Git tag to checkout; if unset, `NEMOCLAW_GIT_REF` is used. |
| `VERBOSE` | `0` | Set `1` for more logs. |

### Examples

Inference already running — only rebuild image and refresh pod:

```bash
./deploy_nemoclaw_k8s.sh --acr-name myregistry
```

Install Dynamo, wait, then build, push, refresh:

```bash
./deploy_nemoclaw_k8s.sh --acr-name myregistry --install-dynamo
```

Custom namespaces:

```bash
./deploy_nemoclaw_k8s.sh \
  --acr-name myregistry \
  --install-dynamo \
  --dynamo-namespace my-dynamo \
  --nemoclaw-namespace my-nemoclaw
```

Custom Dynamo YAML:

```bash
export DYNAMO_DEPLOY_MANIFEST="/path/to/your/deploy.yaml"
./deploy_nemoclaw_k8s.sh --acr-name myregistry --install-dynamo
```

### After you run it

1. Edit `nemoclaw-install/nemoclaw-k8s.yaml`: `CHAT_UI_URL` (must match the URL users open), `DYNAMO_HOST`, `NEMOCLAW_ENDPOINT_URL`, `NEMOCLAW_MODEL` if needed; apply again or rerun the script.
2. Secrets: copy `nemoclaw-install/nemoclaw-secrets.example.yaml` to `nemoclaw-secrets.yaml`, fill keys, align with pod env. The script applies it if the file exists.

## Related paths

- Upstream Nemotron recipes: [github.com/ai-dynamo/dynamo/tree/main/recipes/nemotron-3-super-fp8](https://github.com/ai-dynamo/dynamo/tree/main/recipes/nemotron-3-super-fp8)
- Upstream README (prereqs, quick start): [github.com/ai-dynamo/dynamo/blob/main/recipes/nemotron-3-super-fp8/README.md](https://github.com/ai-dynamo/dynamo/blob/main/recipes/nemotron-3-super-fp8/README.md)
- Workshop copy — default disagg example: `dynamo/dynamo/recipes/nemotron-3-super-fp8/sglang/disagg/deploy.yaml`
- Workshop copy — agg and other paths: `dynamo/dynamo/recipes/nemotron-3-super-fp8/vllm/agg/`, `sglang/agg/`, `trtllm/disagg/`
- Pod YAML: `nemoclaw-install/nemoclaw-k8s.yaml`
