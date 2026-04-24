# AKS workshop: NemoClaw with Azure Container Registry and optional Blob NFS storage

This workshop walks you through running **[NemoClaw](https://github.com/NVIDIA/NemoClaw)** on **Azure Kubernetes Service (AKS)**: you build a small **custom image** (NemoClaw + workshop policy) in **Azure Container Registry (ACR)**, deploy a **Docker-in-Docker** pod whose workspace runs the installer and **OpenClaw** sandboxes under **OpenShell**, expose the **Control UI** with a **LoadBalancer** service, and optionally wire **Azure OpenAI** and **Azure Blob over NFS** for inference keys and durable storage. The goal is a repeatable, self-contained lab environment for governed agent tooling on Azure without cloning the full upstream repo to your laptop.

Create a working directory on your machine, add the files in [Embedded manifests and build files](#embedded-manifests-and-build-files) (copy each fenced block into the path shown above it), then follow [Workshop flow](#workshop-flow). You do not need any other repository checkout to complete the lab.

The NemoClaw **Pod** can mount a **PersistentVolumeClaim** named `pvc-blob` at **`/mnt/blob`** so data survives pod restarts when you use Azure Blob over **NFS v3**. The pod spec does not create that volume; configure storage in [Persistent Azure Blob storage (NFS)](#persistent-azure-blob-storage-nfs) if you use the default manifest. For data to be visible **inside the OpenClaw sandbox**, you must satisfy **both** [OpenShell filesystem policy](#openclaw-sandbox-access-to-mntblob) and [DinD bind-mount placement](#openclaw-sandbox-access-to-mntblob) below—not only the workspace container mount.

Official reference for Blob CSI on AKS: [Create and manage persistent volumes with Azure Blob storage in AKS](https://learn.microsoft.com/en-us/azure/aks/create-volume-azure-blob-storage?tabs=NFS%2Cnfs).

---

## What you will deploy

| Piece | Role |
|-------|------|
| Custom **Docker image** (`nemoclaw-dind-src`) | `node:22` base with a pinned [NemoClaw](https://github.com/NVIDIA/NemoClaw) tree and a workshop policy file copied into the build context, then pushed to your ACR. |
| **Pod** (DinD + workspace) | Workspace runs the NemoClaw installer; image is pulled from ACR; `CHAT_UI_URL` comes from a ConfigMap. |
| **Service** (LoadBalancer) + **NetworkPolicy** | Public HTTP to the Control UI port; unrestricted egress for the labeled pod. |
| **Optional Secret** | Azure OpenAI (and optional other) credentials for the workspace container. |
| **Optional Blob NFS** | StorageClass, static PV, and PVC backing `pvc-blob`. |

---

## Prerequisites

1. **Azure CLI** (`az`), **Docker**, **kubectl**, and **git** on the machine you use for the workshop.
2. An **AKS cluster** with:
   - Workload identity / pull permissions as needed for your ACR (typically `az aks update -n … --attach-acr <acrName>`).
   - The [**Azure Blob CSI driver**](https://learn.microsoft.com/en-us/azure/aks/create-volume-azure-blob-storage?tabs=NFS%2Cnfs) enabled (required for Blob PVs/PVCs on AKS).
3. **ACR** with permission to push `nemoclaw-dind-src:latest` (image will be `\<ACR_NAME\>.azurecr.io/nemoclaw-dind-src:latest`).
4. For **NFS Blob** (persistent workshop storage): a storage account created **with NFS v3 support** (NFS cannot be turned on for an existing non-NFS account). See [NFS 3.0 support for Azure Blob](https://learn.microsoft.com/en-us/azure/storage/blobs/network-file-system-protocol-support-how-to).
5. For **NFS with private networking**: Microsoft documents that the AKS **cluster identity** may need **Contributor** on the virtual network and NSG when using NFS; follow the networking guidance in the same [AKS Blob volume article](https://learn.microsoft.com/en-us/azure/aks/create-volume-azure-blob-storage?tabs=NFS%2Cnfs).

---

## Embedded manifests and build files

Create a directory for the workshop (examples below use `~/nemoclaw-workshop` and assume your shell is **in that directory**). For each subsection, create the listed path and paste the YAML or Dockerfile exactly.

### Policy file for the image build

Create `nemoclaw-blueprint/policies/openclaw-sandbox.yaml`:

```yaml
# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0
#
# OpenClaw sandbox network policy (development / lab). Egress CONNECT is
# allowed to resolved addresses in the full IPv4/IPv6 allowlist on TCP ports
# 80 and 443 only. Loopback and link-local remain blocked inside OpenShell.
# Kubernetes API/etcd/kubelet ports remain hard-blocked in the proxy regardless
# of policy — see OpenShell BLOCKED_CONTROL_PLANE_PORTS.
#
# To add endpoints: update this file and re-run `nemoclaw onboard`
# or apply dynamically via `openshell policy set`.

version: 1

filesystem_policy:
  include_workdir: false
  read_only:
    - /usr
    - /lib
    - /proc
    - /dev/urandom
    - /app
    - /etc
    - /var/log
    # With /mnt/blob below, include /mnt read_only so Landlock allows traversing
    # the parent (otherwise `ls /mnt` fails inside the sandbox).
    - /mnt
  read_write:
    - /sandbox
    - /tmp
    - /dev/null
    - /sandbox/.openclaw
    - /sandbox/.openclaw-data
    # When using pvc-blob, add /mnt/blob (read_only or read_write) — see
    # "OpenClaw sandbox access to /mnt/blob" under Persistent Azure Blob storage.
    - /mnt/blob

landlock:
  compatibility: best_effort

process:
  run_as_user: sandbox
  run_as_group: sandbox

network_policies:
  unrestricted:
    name: unrestricted
    endpoints:
      - allowed_ips:
          - "0.0.0.0/0"
          - "::/0"
        access: full
        ports:
          - 80
          - 443
    binaries:
      - { path: "/**" }
```

### Dockerfile for `nemoclaw-dind-src`

Create `Dockerfile` in the workshop root (same directory you will run `docker build` from):

```dockerfile
# NemoClaw baked into node image for DinD workspace jobs.
FROM node:22

ENV OPENSHELL_LOG_LEVEL=debug

COPY ./nemoclaw-src/NemoClaw /nemoclaw-src
COPY ./nemoclaw-blueprint /nemoclaw-src/nemoclaw-blueprint

RUN curl -LsSf https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh | OPENSHELL_VERSION=v0.0.26 sh
```

### LoadBalancer Service and NetworkPolicy

Create `nemoclaw-egress.yaml`:

```yaml
# Public HTTP LoadBalancer for NemoClaw (default namespace: nemoclaw).
# - Service: port 80 -> targetPort 18789 on the workspace container.
# - NetworkPolicy: allow all egress for pods with labels app=nemoclaw and nemoclaw.io/instance.
#
# Prerequisites:
# - Pod must set CHAT_UI_URL to a non-loopback URL so the dashboard forward binds 0.0.0.0:18789.
# - CHAT_UI_URL must match the public origin users open in the browser for allowedOrigins.
# - Wait until the Service shows a real EXTERNAL-IP or hostname instead of <pending>.
---
apiVersion: v1
kind: Service
metadata:
  name: nemoclaw-http
  namespace: nemoclaw
  labels:
    app: nemoclaw
spec:
  type: LoadBalancer
  selector:
    app: nemoclaw
    nemoclaw.io/instance: nemoclaw
  ports:
    - name: http
      port: 80
      targetPort: 18789
      protocol: TCP
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: nemoclaw-allow-all-egress
  namespace: nemoclaw
  labels:
    app: nemoclaw
spec:
  podSelector:
    matchLabels:
      app: nemoclaw
      nemoclaw.io/instance: nemoclaw
  policyTypes:
    - Egress
  egress:
    - {}
```

### NemoClaw Pod

Create `nemoclaw-k8s.yaml`. Replace placeholder values (ACR host, endpoints, model, tokens) **before** applying, or rely on the `sed` / `kubectl` steps in the workshop flow for the image registry only.

```yaml
# NemoClaw on Kubernetes — Docker-in-Docker + workspace installer.
#
# Before apply: kubectl create namespace nemoclaw (or your chosen namespace).
# Replace the workspace image with YOUR_ACR.azurecr.io/nemoclaw-dind-src:latest
# Replace NEMOCLAW_ENDPOINT_URL, NEMOCLAW_MODEL, DYNAMO_HOST, GITHUB_TOKEN as needed.
#
# CHAT_UI_URL: supplied from a ConfigMap (e.g. nemoclaw-lb-config) after the
# LoadBalancer Service has a public address — see workshop flow.
#
# Optional Secret nemoclaw-workshop-credentials (key azure-openai-api-key):
# if absent, COMPATIBLE_API_KEY defaults to dummy in the startup script.
#
# pvc-blob: mount blob01 at /mnt/blob on BOTH dind and workspace so Docker
# bind-mounts into OpenClaw sandboxes resolve on the dockerd host — see README
# "OpenClaw sandbox access to /mnt/blob".
apiVersion: v1
kind: Pod
metadata:
  name: nemoclaw
  namespace: nemoclaw
  labels:
    app: nemoclaw
    nemoclaw.io/instance: nemoclaw
spec:
  containers:
    - name: dind
      image: docker:24-dind
      securityContext:
        privileged: true
      env:
        - name: DOCKER_TLS_CERTDIR
          value: ""
      command: ["dockerd", "--host=unix:///var/run/docker.sock"]
      volumeMounts:
        - name: docker-storage
          mountPath: /var/lib/docker
        - name: docker-socket
          mountPath: /var/run
        - name: docker-config
          mountPath: /etc/docker
        - name: blob01
          mountPath: "/mnt/blob"
          readOnly: false
      resources:
        requests:
          memory: "8Gi"
          cpu: "2"

    - name: workspace
      image: anslutskynemoclawclusterregistry.azurecr.io/nemoclaw-dind-src:latest
      command:
        - bash
        - -c
        - |
          set -e

          echo "[1/4] Installing packages..."
          apt-get update -qq
          apt-get install -y -qq docker.io socat curl >/dev/null 2>&1

          apt-get install git -y -qq

          echo "[2/4] Starting socat proxy..."
          socat TCP-LISTEN:8000,fork,reuseaddr TCP:$DYNAMO_HOST &
          echo "127.0.0.1 host.openshell.internal" >> /etc/hosts
          sleep 1

          echo "[3/4] Waiting for Docker daemon..."
          for i in $(seq 1 30); do
            if docker info >/dev/null 2>&1; then break; fi
            sleep 2
          done
          docker info >/dev/null 2>&1 || { echo "Docker not ready"; exit 1; }
          echo "Docker ready"

          export COMPATIBLE_API_KEY="${COMPATIBLE_API_KEY:-dummy}"

          export NEMOCLAW_REPO_ROOT=/nemoclaw-src

          echo "[4/4] Running NemoClaw installer..."
          umask 077
          bash /nemoclaw-src/scripts/install.sh --non-interactive --yes-i-accept-third-party-software

          echo "Onboard complete. Container staying alive!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
          exec sleep infinity
      env:
        - name: CHAT_UI_URL
          valueFrom:
            configMapKeyRef:
              name: nemoclaw-lb-config
              key: CHAT_UI_URL
        - name: DOCKER_HOST
          value: unix:///var/run/docker.sock
        - name: DYNAMO_HOST
          value: "YOUR-DYNAMO-FRONTEND.dynamo-system.svc.cluster.local:8000"
        - name: NEMOCLAW_NON_INTERACTIVE
          value: "1"
        - name: NEMOCLAW_PROVIDER
          value: "custom"
        - name: NEMOCLAW_ENDPOINT_URL
          value: "https://YOUR_RESOURCE.openai.azure.com/openai/v1/"
        - name: COMPATIBLE_API_KEY
          valueFrom:
            secretKeyRef:
              name: nemoclaw-workshop-credentials
              key: azure-openai-api-key
              optional: true
        - name: NEMOCLAW_MODEL
          value: "YOUR_AZURE_OPENAI_DEPLOYMENT_NAME"
        - name: NEMOCLAW_SANDBOX_NAME
          value: "my-assistant"
        - name: NEMOCLAW_WORKSHOP_POLICY_SRC
          value: "/nemoclaw-src/nemoclaw-blueprint/policies/openclaw-sandbox.yaml"
        - name: NEMOCLAW_POLICY_MODE
          value: "suggested"
        - name: NEMOCLAW_ACCEPT_THIRD_PARTY_SOFTWARE
          value: "1"
        - name: NEMOCLAW_FROM_DOCKERFILE
          value: "/nemoclaw-src/Dockerfile"
        - name: GITHUB_TOKEN
          value: "<your token>"
      volumeMounts:
        - name: docker-socket
          mountPath: /var/run
        - name: docker-config
          mountPath: /etc/docker
        - name: blob01
          mountPath: "/mnt/blob"
          readOnly: false
      resources:
        requests:
          memory: "4Gi"
          cpu: "2"
      ports:
        - containerPort: 18789
          name: dashboard
          protocol: TCP

  initContainers:
    - name: init-docker-config
      image: busybox
      command: ["sh", "-c", "echo '{\"default-cgroupns-mode\":\"host\"}' > /etc/docker/daemon.json"]
      volumeMounts:
        - name: docker-config
          mountPath: /etc/docker

  volumes:
    - name: docker-storage
      emptyDir: {}
    - name: docker-socket
      emptyDir: {}
    - name: docker-config
      emptyDir: {}
    - name: blob01
      persistentVolumeClaim:
        claimName: pvc-blob

  restartPolicy: Never
```

### Optional Secret (Azure OpenAI and related)

Create `nemoclaw-secrets.yaml` only if you want a real API key (otherwise skip applying this file):

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: nemoclaw-workshop-credentials
  namespace: nemoclaw
type: Opaque
stringData:
  azure-openai-api-key: REPLACE_ME
  NGC_KEY: REPLACE_ME
```

Edit the values, then apply in [Step 2](#step-2--optional-azure-openai-and-other-secrets).

### NFS StorageClass (optional persistent storage)

Create `blob-nfs-sc.yaml`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: azureblob-nfs-premium
provisioner: blob.csi.azure.com
parameters:
  protocol: nfs
  tags: environment=Development
volumeBindingMode: Immediate
allowVolumeExpansion: true
mountOptions:
  - nconnect=4
```

### Static NFS PersistentVolume (optional)

Create `pv-blob-nfs.yaml` and replace `volumeHandle`, `resourceGroup`, `storageAccount`, and `containerName` with **your** Azure resources:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  annotations:
    pv.kubernetes.io/provisioned-by: blob.csi.azure.com
  name: pv-blob
spec:
  capacity:
    storage: 1Pi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: azureblob-nfs-premium
  mountOptions:
    - nconnect=4
  csi:
    driver: blob.csi.azure.com
    volumeHandle: YOUR_STORAGEACCOUNT_YOUR_CONTAINER
    volumeAttributes:
      resourceGroup: YOUR_RG
      storageAccount: YOUR_STORAGE_ACCOUNT
      containerName: YOUR_CONTAINER
      protocol: nfs
```

### PersistentVolumeClaim for the static PV (optional)

Create `pvc-blob-nfs.yaml`:

```yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: pvc-blob
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 10Gi
  volumeName: pv-blob
  storageClassName: azureblob-nfs-premium
```

### Alternative: dynamic PVC (optional)

If you prefer a **dynamically** provisioned claim instead of the static PV/PVC pair, create `pvc-blob-dynamic.yaml` and change the pod volume’s `claimName` to match `metadata.name` here (`azure-blob-storage`):

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: azure-blob-storage
spec:
  accessModes:
  - ReadWriteMany
  storageClassName: azureblob-nfs-premium
  resources:
    requests:
      storage: 5Gi
```

---

## Workshop flow

All shell commands assume you have `cd`’d into the **same directory** where you created `Dockerfile`, `nemoclaw-k8s.yaml`, `nemoclaw-egress.yaml`, and the `nemoclaw-blueprint/` tree.

### Step 0 — Log in and choose names

```bash
az login
az aks get-credentials --resource-group <RG> --name <AKS_CLUSTER>
```

```bash
export ACR_NAME=<your-acr-short-name>
export NEMOCLAW_NAMESPACE=nemoclaw
export NEMOCLAW_POD_NAME=nemoclaw
export NEMOCLAW_LB_SVC_NAME="${NEMOCLAW_POD_NAME}-http"
export NEMOCLAW_LB_CONFIGMAP_NAME="${NEMOCLAW_POD_NAME}-lb-config"
```

```bash
kubectl create namespace "${NEMOCLAW_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
```

### Step 1 — (Optional) Persistent Azure Blob over NFS

Follow [Persistent Azure Blob storage (NFS)](#persistent-azure-blob-storage-nfs) using the `blob-nfs-sc.yaml`, `pv-blob-nfs.yaml`, and `pvc-blob-nfs.yaml` files you created. If you skip storage, remove or adjust the `persistentVolumeClaim` volume in your pod manifest so the pod does not wait on a missing claim.

### Step 2 — (Optional) Azure OpenAI and other secrets

If you created `nemoclaw-secrets.yaml`:

```bash
kubectl apply -f ./nemoclaw-secrets.yaml -n "${NEMOCLAW_NAMESPACE}"
```

If you skip this, the startup script defaults `COMPATIBLE_API_KEY` to `dummy` when the Secret is absent.

### Step 3 — (Optional) Deploy Dynamo first

If you use NVIDIA Dynamo’s disaggregated SGLang stack in-cluster, apply the manifests from the [ai-dynamo/dynamo](https://github.com/ai-dynamo/dynamo) project (for example under `recipes/` for your model) or your own packaging into a namespace such as `dynamo-system`, then wait until every pod there is **Running** with full readiness and your frontend service matches the `DYNAMO_HOST` value in your pod spec.

Skip this step if you already have an inference endpoint; update `DYNAMO_HOST` and `NEMOCLAW_ENDPOINT_URL` in the pod YAML you saved before applying.

### Step 4 — Pin NemoClaw sources for the image build

```bash
export NEMOCLAW_GIT_URL=https://github.com/NVIDIA/NemoClaw.git
export NEMOCLAW_GIT_TAG=v0.0.18
mkdir -p nemoclaw-src
rm -rf nemoclaw-src/NemoClaw
git clone --depth 1 --branch "${NEMOCLAW_GIT_TAG}" "${NEMOCLAW_GIT_URL}" nemoclaw-src/NemoClaw
```

### Step 5 — Build and push the workshop image

```bash
docker build --platform linux/amd64 -t "${ACR_NAME}.azurecr.io/nemoclaw-dind-src:latest" .
```

```bash
docker push "${ACR_NAME}.azurecr.io/nemoclaw-dind-src:latest"
# If unauthorized:
az acr login --name "${ACR_NAME}"
docker push "${ACR_NAME}.azurecr.io/nemoclaw-dind-src:latest"
```

### Step 6 — LoadBalancer, ConfigMap, and NemoClaw pod

```bash
if [[ -f ./nemoclaw-secrets.yaml ]]; then
  kubectl apply -f ./nemoclaw-secrets.yaml -n "${NEMOCLAW_NAMESPACE}"
fi
```

**6a — Egress**

If you use the defaults in the pasted YAML (`namespace: nemoclaw`, Service `nemoclaw-http`, instance `nemoclaw`):

```bash
kubectl apply -f ./nemoclaw-egress.yaml
```

If you changed namespace, Service name, or instance label, pipe the file through `sed` so those fields stay aligned:

```bash
sed -e "s|^[[:space:]]*namespace: nemoclaw|  namespace: ${NEMOCLAW_NAMESPACE}|g" \
  -e "s|^  name: nemoclaw-http\$|  name: ${NEMOCLAW_LB_SVC_NAME}|" \
  -e "s|^  name: nemoclaw-allow-all-egress\$|  name: ${NEMOCLAW_POD_NAME}-allow-all-egress|" \
  -e "s|nemoclaw.io/instance: nemoclaw|nemoclaw.io/instance: ${NEMOCLAW_POD_NAME}|g" \
  ./nemoclaw-egress.yaml | kubectl apply -f - -n "${NEMOCLAW_NAMESPACE}"
```

**6b — Wait for the LoadBalancer address**

```bash
kubectl get svc -n "${NEMOCLAW_NAMESPACE}" "${NEMOCLAW_LB_SVC_NAME}" -w
```

**6c — ConfigMap**

```bash
export LB_ADDR=<paste-external-ip-or-hostname>
export CHAT_UI_URL="http://${LB_ADDR}"
```

For IPv6 addresses (not hostnames), use `export CHAT_UI_URL="http://[${LB_ADDR}]"`.

```bash
kubectl create configmap "${NEMOCLAW_LB_CONFIGMAP_NAME}" -n "${NEMOCLAW_NAMESPACE}" \
  --from-literal="LOAD_BALANCER_IP=${LB_ADDR}" \
  --from-literal="CHAT_UI_URL=${CHAT_UI_URL}" \
  --dry-run=client -o yaml | kubectl apply -f - -n "${NEMOCLAW_NAMESPACE}"
```

**6d — Pod manifest**

The embedded pod example uses a placeholder ACR host. Replace it with your registry (and optionally namespace, pod name, ConfigMap name, instance label):

```bash
kubectl delete pod "${NEMOCLAW_POD_NAME}" -n "${NEMOCLAW_NAMESPACE}" --ignore-not-found
sed -e "s|anslutskynemoclawclusterregistry.azurecr.io|${ACR_NAME}.azurecr.io|g" \
  ./nemoclaw-k8s.yaml | kubectl apply -f - -n "${NEMOCLAW_NAMESPACE}"
```

For custom namespace or pod name:

```bash
kubectl delete pod "${NEMOCLAW_POD_NAME}" -n "${NEMOCLAW_NAMESPACE}" --ignore-not-found
sed -e "s|anslutskynemoclawclusterregistry.azurecr.io|${ACR_NAME}.azurecr.io|g" \
  -e "s|^[[:space:]]*namespace: nemoclaw|  namespace: ${NEMOCLAW_NAMESPACE}|g" \
  -e "s|name: nemoclaw-lb-config|name: ${NEMOCLAW_LB_CONFIGMAP_NAME}|g" \
  -e "s|^  name: nemoclaw\$|  name: ${NEMOCLAW_POD_NAME}|" \
  -e "s|nemoclaw.io/instance: nemoclaw|nemoclaw.io/instance: ${NEMOCLAW_POD_NAME}|g" \
  ./nemoclaw-k8s.yaml | kubectl apply -f - -n "${NEMOCLAW_NAMESPACE}"
```

### Step 7 — Verify

```bash
kubectl get pods,svc,configmap -n "${NEMOCLAW_NAMESPACE}"
kubectl get configmap "${NEMOCLAW_LB_CONFIGMAP_NAME}" -n "${NEMOCLAW_NAMESPACE}" -o yaml
```

Open the Control UI at the `CHAT_UI_URL` value you stored in the ConfigMap (same origin users type in the browser).

---

## Persistent Azure Blob storage (NFS)

This section aligns with Microsoft’s **static NFS PV** flow: [Create a static PV with Azure Blob storage](https://learn.microsoft.com/en-us/azure/aks/create-volume-azure-blob-storage?tabs=NFS%2Cnfs) (NFS tab).

### Why NFS here

The default pod manifest requests shared access via a single PVC (`pvc-blob`) mounted at `/mnt/blob`. NFS v3 against Azure Blob matches the CSI driver `blob.csi.azure.com`.

### Azure-side preparation

1. **Enable the Blob CSI driver** on the cluster if it is not already (see [prerequisites in the Microsoft article](https://learn.microsoft.com/en-us/azure/aks/create-volume-azure-blob-storage?tabs=NFS%2Cnfs)).
2. **Create a storage account with NFS v3 enabled** and a **container** for your data.
3. **Network**: Ensure nodes can reach the blob endpoint per [Mount Blob Storage by using NFS 3.0](https://learn.microsoft.com/en-us/azure/storage/blobs/network-file-system-protocol-support-how-to) and the AKS article’s networking notes.

### Apply StorageClass, PV, and PVC

After editing `pv-blob-nfs.yaml` for your account:

```bash
kubectl apply -f ./blob-nfs-sc.yaml
kubectl apply -f ./pv-blob-nfs.yaml
kubectl apply -f ./pvc-blob-nfs.yaml -n nemoclaw
```

If your NemoClaw namespace is not `nemoclaw`, apply the PVC to `${NEMOCLAW_NAMESPACE}` instead.

| Field (in PV) | Purpose |
|---------------|---------|
| `metadata.name` | PV name; must match `volumeName` in the PVC unless you change both. |
| `spec.storageClassName` | Must match the StorageClass (`azureblob-nfs-premium` above). |
| `spec.csi.volumeHandle` | **Unique** ID per blob container in the cluster (e.g. `storageaccount_container`). Do **not** use `#` or `/`. |
| `spec.csi.volumeAttributes.*` | Your resource group, storage account, container, and `protocol: nfs`. |

**Capacity** on the PV is mainly for scheduling; a large value (for example `1Pi`) avoids binding issues.

```bash
kubectl get pv pv-blob
kubectl get pvc pvc-blob -n nemoclaw
```

### Optional: quick mount test

Use a small test pod mounting `pvc-blob` at `/mnt/blob` (as in the Microsoft article) to validate storage before running the full installer.

### OpenClaw sandbox access to `/mnt/blob`

The **workspace** container and the **OpenClaw** process inside it can see `/mnt/blob` as soon as the PVC is mounted on that container. The **OpenClaw sandbox** is a separate Linux environment (child **Docker** container) managed by **OpenShell**. Two independent things must be true for `/mnt/blob` to exist and be usable there.

#### 1. OpenShell filesystem policy (Landlock and mount preparation)

OpenShell only exposes paths listed under `filesystem_policy.read_only` or `filesystem_policy.read_write` in `nemoclaw-blueprint/policies/openclaw-sandbox.yaml`. Add **`/mnt/blob`** to one of those lists (use **`read_only`** for datasets you do not want the agent to mutate; **`read_write`** when the agent should persist files on the share).

Also add **`/mnt`** under **`read_only`**. Landlock applies to path prefixes used for traversal; if only `/mnt/blob` is listed, **`ls /mnt`** (and sometimes discovering the mount) can return **Permission denied** even when `/mnt/blob` is intended to be available. Listing **`/mnt`** stays read-only; keep the actual share writable only if **`/mnt/blob`** is under `read_write`.

After editing the policy file, apply it the same way you normally refresh policy—for example re-run **`nemoclaw onboard`**, or on a running sandbox use **`openshell policy set --policy <file> <sandbox-name>`** (see NemoClaw docs on network policies / policy tiers).

**Check that the loaded policy includes your path** (from a shell in the workspace container, with `NEMOCLAW_SANDBOX_NAME` or your sandbox name):

```bash
openshell policy get --full my-assistant
```

Confirm `filesystem_policy` lists `/mnt/blob` and that **`openshell policy list my-assistant`** shows the latest version as **Loaded**, not stuck in **Pending**.

If policy shows `/mnt/blob` but the path is **missing** inside the sandbox, check DinD mounts (subsection 2). If `/mnt/blob` **exists** but **`ls /mnt/blob` shows no files** while workspace and `dind` show PVC contents, read subsection 4 (OpenShell creates an empty directory when the Docker bind is absent).

#### 2. DinD: bind-mount source must live on the `dockerd` container

The **`dind`** container runs **`dockerd`**. When OpenShell creates the OpenClaw sandbox container, Docker bind-mounts host paths from **the filesystem where `dockerd` runs**—that is, inside **`dind`**, not inside **`workspace`**.

If `pvc-blob` is mounted only on **`workspace`**, then `ls /mnt/blob` succeeds on the workspace shell but **`/mnt/blob` on the Docker host (`dind`) is not your PVC**. Sandbox containers therefore do not receive the blob volume, even when policy allows `/mnt/blob`.

**Fix:** Mount the same PVC volume (`blob01` in the example manifest) at **`/mnt/blob` on both containers**—`dind` and `workspace`—as in `nemoclaw-install/nemoclaw-k8s.yaml` and the embedded pod YAML above. Recreate the pod after changing mounts.

**Sanity checks:**

```bash
kubectl exec -n nemoclaw nemoclaw -c workspace -- ls -la /mnt/blob
kubectl exec -n nemoclaw nemoclaw -c dind -- ls -la /mnt/blob
```

Both should list the same backing storage. If `dind` cannot see the volume, fix the pod spec before debugging OpenClaw further.

#### 3. Recreate the sandbox if it was started before the fix

Existing sandbox containers keep their old bind configuration until recreated. After fixing the pod and policy, restart or recreate the sandbox (or the whole pod) so a new container is created with the correct mounts.

#### 4. Empty `/mnt/blob` (path exists, `ls` shows no files)

Policy and Landlock only **allow** paths; they do **not** by themselves configure **Docker** to bind the DinD host’s `/mnt/blob` into the **inner** OpenClaw sandbox container.

OpenShell’s supervisor runs **`prepare_filesystem()`** before the sandboxed process starts. For every path in **`filesystem_policy.read_write`**, if the path is **not** already present in the container rootfs, OpenShell **creates it** with `create_dir_all` (see [OpenShell sandbox architecture — Filesystem preparation](https://github.com/NVIDIA/OpenShell/blob/main/architecture/sandbox.md)). If the sandbox container was **never** given a host bind such as **`-v /mnt/blob:/mnt/blob`** from the machine where **`dockerd`** runs (`dind`), then **`/mnt/blob` does not exist** when that code runs → OpenShell creates an **empty directory** → you can `cd` and `ls` there, but you **do not** see PVC files. Mounting the PVC on **`dind`** is **necessary** for a future host bind to work, but **not sufficient** unless whatever **creates** the sandbox container (NemoClaw + OpenShell / gateway / community image) actually passes that volume through to `docker run` / the equivalent API.

**Confirm from the workspace shell** (same host that talks to DinD’s socket):

List containers with images so you pick the **OpenClaw sandbox** workload, **not** the OpenShell cluster container:

```bash
docker ps -a --format '{{.ID}}\t{{.Names}}\t{{.Image}}'
```

Ignore **`openshell-cluster-*`** (it mounts Docker volumes such as `/var/lib/rancher/k3s` for the in-cluster OpenShell control plane). That container is **not** the per-assistant OpenClaw sandbox where **`nemoclaw … connect`** runs. Inspect the container whose **image** or **name** matches your **OpenClaw** sandbox (often a separate ID/name from `openshell-cluster-nemoclaw`).

```bash
docker inspect "<SANDBOX_WORKLOAD_CONTAINER_ID>" --format '{{json .Mounts}}'
```

If **`jq`** is not installed, pipe through **`python3 -m json.tool`** when Python is available, or read the one-line JSON as-is.

Look for a mount whose **`Destination`** is **`/mnt/blob`**. The **`Source`** should be a path on the **`dind`** filesystem that backs your PVC (the same tree `kubectl exec … -c dind -- ls /mnt/blob` shows). If **`/mnt/blob` is absent from `Mounts`**, the empty directory behavior above is expected until upstream tooling gains an explicit extra bind for your deployment.

**If a bind exists but listings still disagree**, compare **`ls -la /mnt/blob`** in workspace, `dind`, and the sandbox. NFS **root squashing** or **mode 0700** directories owned by root on the share can hide names from the unprivileged **`sandbox`** user even when the mount is correct.

**Practical workarounds** when live PVC pass-through is not wired into sandbox creation yet: copy artifacts with **`openshell sandbox upload`** (see NemoClaw backup/restore docs), or stage data under paths the default image already bind-mounts (for example under **`/sandbox`** if your flow supports that).

---

## Workshop parameters (quick reference)

| Item | Typical value |
|------|----------------|
| `ACR_NAME` | Short ACR name (`\<name\>.azurecr.io`). |
| `NEMOCLAW_NAMESPACE` | `nemoclaw` |
| `NEMOCLAW_POD_NAME` | `nemoclaw` |
| `NEMOCLAW_LB_SVC_NAME` | `\<NEMOCLAW_POD_NAME\>-http` |
| `NEMOCLAW_LB_CONFIGMAP_NAME` | `\<NEMOCLAW_POD_NAME\>-lb-config` |
| `NEMOCLAW_GIT_TAG` | `v0.0.18` |

---

## Troubleshooting

| Symptom | Check |
|---------|-------|
| Pod pending on `pvc-blob` | PVC missing, wrong namespace, PV not `Bound`, or StorageClass / `volumeHandle` / account mismatch. |
| LoadBalancer stays pending | `kubectl get svc -n nemoclaw`; Azure LB SKU / quota. |
| Push auth failure | `az acr login --name <ACR_NAME>`; ACR firewall / identity. |
| Control UI “origin not allowed” | `CHAT_UI_URL` in the ConfigMap must match the browser origin (scheme + host + port). |
| NFS mount errors | NFS v3 on account, network path from nodes, CSI driver, RBAC per Microsoft docs. |
| `/mnt/blob` missing inside OpenClaw despite policy showing it | Mount **`pvc-blob` at `/mnt/blob` on `dind` as well as `workspace`** ([OpenClaw sandbox access to `/mnt/blob`](#openclaw-sandbox-access-to-mntblob)); confirm with `kubectl exec … -c dind -- ls /mnt/blob`. Recreate the sandbox pod after changes. |
| `ls /mnt` → Permission denied inside sandbox | Add **`/mnt`** to **`filesystem_policy.read_only`** alongside `/mnt/blob`, then **`openshell policy set`** or re-onboard and reconnect (`nemoclaw … connect`). |
| `/mnt/blob` exists in sandbox but is **empty** while workspace/`dind` have files | Policy + DinD are not enough: the **sandbox container** needs a **Docker bind** for `/mnt/blob` from the `dind` host. If **`docker inspect` → `Mounts`** has no `/mnt/blob`, OpenShell’s **`prepare_filesystem()`** likely created an **empty** `read_write` directory ([Empty `/mnt/blob`](#4-empty-mntblob-path-exists-ls-shows-no-files)). Use **`openshell sandbox upload`**, stage under **`/sandbox`**, or follow upstream for extra sandbox volumes. |
