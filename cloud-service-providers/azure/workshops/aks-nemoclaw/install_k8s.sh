#!/usr/bin/env bash
# Build nemoclaw-base image for linux/amd64, push to ACR, refresh the nemoclaw pod.
# Run from anywhere; paths are resolved relative to this script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${SCRIPT_DIR}/nemoclaw-base"
INSTALL_DIR="${SCRIPT_DIR}/nemoclaw-install"
# Short ACR name only (e.g. myregistry) — not the full login server.
ACR_NAME="${ACR_NAME:?Set ACR_NAME to your Azure Container Registry name (az acr list -o table)}"
IMAGE="${ACR_NAME}.azurecr.io/nemoclaw-dind-src:latest"

log() {
  printf '%s\n' "$*" >&2
}

is_push_auth_failure() {
  local file="$1"
  grep -qiE \
    'unauthorized|authentication required|401: Unauthorized|no basic auth credentials|error getting credentials|denied: requested access to the resource is denied' \
    "$file"
}

push_with_acr_retry() {
  local err
  err="$(mktemp)"
  trap 'rm -f "${err}"' RETURN

  set +e
  docker push "${IMAGE}" 2>&1 | tee "${err}"
  local rc=${PIPESTATUS[0]}
  set -e

  if [[ "${rc}" -eq 0 ]]; then
    return 0
  fi

  if is_push_auth_failure "${err}"; then
    log "Docker push failed with an authentication or registry access error."
    log "Running: az acr login --name ${ACR_NAME}"
    az acr login --name "${ACR_NAME}"
    docker push "${IMAGE}"
    return 0
  fi

  log "Docker push failed (exit ${rc}) and output did not match known auth errors; not retrying."
  return "${rc}"
}

[[ -d "${BASE_DIR}" ]] || { log "Missing directory: ${BASE_DIR}"; exit 1; }
[[ -d "${INSTALL_DIR}" ]] || { log "Missing directory: ${INSTALL_DIR}"; exit 1; }
[[ -f "${INSTALL_DIR}/nemoclaw-k8s.yaml" ]] || { log "Missing file: ${INSTALL_DIR}/nemoclaw-k8s.yaml"; exit 1; }

log "Building ${IMAGE} in ${BASE_DIR}..."
(
  cd "${BASE_DIR}"
  docker build --platform linux/amd64 -t "${IMAGE}" .
)

log "Pushing ${IMAGE}..."
push_with_acr_retry

log "Recreating nemoclaw pod in namespace nemoclaw..."
(
  cd "${INSTALL_DIR}"
  if [[ -f ./nemoclaw-secrets.yaml ]]; then
    log "Applying ./nemoclaw-secrets.yaml (gitignored local credentials)."
    kubectl apply -f ./nemoclaw-secrets.yaml -n nemoclaw
  else
    log "No ./nemoclaw-secrets.yaml — Azure key must be supplied for real Azure OpenAI."
    log "Copy nemoclaw-secrets.example.yaml to nemoclaw-secrets.yaml, edit, and re-run."
  fi
  kubectl delete pod nemoclaw -n nemoclaw --ignore-not-found
  # Substitute registry from ACR_NAME; edit CHAT_UI_URL / Azure URLs in nemoclaw-k8s.yaml separately.
  sed "s|anslutskynemoclawclusterregistry.azurecr.io|${ACR_NAME}.azurecr.io|g" ./nemoclaw-k8s.yaml | kubectl apply -f - -n nemoclaw
)

log "Done."
