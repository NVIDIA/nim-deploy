#!/usr/bin/env bash
# Build nemoclaw-base image for linux/amd64, push to ACR, refresh the nemoclaw pod.
# Run from anywhere; paths are resolved relative to this script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="${SCRIPT_DIR}/nemoclaw-base"
INSTALL_DIR="${SCRIPT_DIR}/nemoclaw-install"
NEMOCLAW_SRC="${BASE_DIR}/nemoclaw-src"
# Upstream NemoClaw is cloned here (other paths under nemoclaw-src are left untouched).
NEMOCLAW_REPO_DIR="${NEMOCLAW_SRC}/NemoClaw"
NEMOCLAW_GIT_URL="${NEMOCLAW_GIT_URL:-https://github.com/NVIDIA/NemoClaw.git}"
# Pin to a git tag (not a branch). NEMOCLAW_GIT_REF is a legacy alias when NEMOCLAW_GIT_TAG is unset.
NEMOCLAW_GIT_TAG="${NEMOCLAW_GIT_TAG:-${NEMOCLAW_GIT_REF:-v0.0.18}}"

# -----------------------------------------------------------------------------
# Dynamo deploy (optional; used when passing --install-dynamo)
# -----------------------------------------------------------------------------
NEMOCLAW_NAMESPACE="${NEMOCLAW_NAMESPACE:-}"
DYNAMO_NAMESPACE="${DYNAMO_NAMESPACE:-}"

DYNAMO_DEPLOY_MANIFEST="${DYNAMO_DEPLOY_MANIFEST:-${SCRIPT_DIR}/dynamo/dynamo/recipes/nemotron-3-super-fp8/sglang/disagg/deploy.yaml}"
DYNAMO_READY_POLL_INTERVAL="${DYNAMO_READY_POLL_INTERVAL:-15}"
DYNAMO_READY_TIMEOUT_SEC="${DYNAMO_READY_TIMEOUT_SEC:-3600}"
DYNAMO_DISAGG_MIN_PODS="${DYNAMO_DISAGG_MIN_PODS:-3}"

# Short ACR name only (e.g. myregistry) — not the full login server.
ACR_NAME="${ACR_NAME:-}"

INSTALL_DYNAMO=0
VERBOSE="${VERBOSE:-0}"

log() {
  printf '%s\n' "$*" >&2
}

# stderr presentation (colors only when stderr is a TTY)
if [[ -t 2 ]]; then
  _R=$'\033[0m'
  _B=$'\033[1m'
  _D=$'\033[2m'
  _K=$'\033[90m'
  _C=$'\033[36m'
  _G=$'\033[32m'
  _Y=$'\033[33m'
  _E=$'\033[31m'
else
  _R= _B= _D= _K= _C= _G= _Y= _E=
fi

log_verbose() {
  [[ "${VERBOSE}" == "1" ]] || return 0
  printf '%s%s%s\n' "${_D}" "$*" "${_R}" >&2
}

section() {
  local title="$1"
  local detail="${2:-}"
  printf '\n%s▶ %s%s' "${_B}${_C}" "${title}" "${_R}" >&2
  [[ -n "${detail}" ]] && printf ' %s%s%s' "${_D}" "${detail}" "${_R}" >&2
  printf '\n' >&2
  printf '%s%s%s\n' "${_K}" "────────────────────────────────────────────────────────────" "${_R}" >&2
}

section_end_ok() {
  printf '%s%s%s %s\n' "${_K}" "────────────────────────────────────────────────────────────" "${_R}" "${_B}${_G}✓${_R} ${1}" >&2
  printf '\n' >&2
}

section_end_err() {
  printf '%s%s%s %s\n' "${_K}" "────────────────────────────────────────────────────────────" "${_R}" "${_B}${_E}✗${_R} ${1}" >&2
  printf '\n' >&2
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Build nemoclaw-base for linux/amd64, push to ACR, and refresh the nemoclaw pod
in Kubernetes. Run from the aks-nemoclaw workshop directory context; paths
resolve relative to this script.

Required (flag or environment variable):
  --acr-name NAME                 Azure Container Registry short name (az acr list -o table).
                                  Same as ACR_NAME.

Options:
  --install-dynamo   Before docker build/push, apply the Dynamo disaggregated
                     SGLang manifest to the cluster (then image build/push and
                     NemoClaw kubectl steps):
                     kubectl apply -f "\${DYNAMO_DEPLOY_MANIFEST}" -n "\${DYNAMO_NAMESPACE}"
                     then wait until all pods in that namespace are Running/Ready
                     and there are at least 3 ready pods per disagg tier (decode,
                     frontend, prefill). Optional Dynamo settings below.
  -h, --help         Show this help and exit.

Optional (flags or environment variables; defaults shown):
  --nemoclaw-namespace NS   NemoClaw kubectl namespace (default: nemoclaw).
  --dynamo-namespace NS     Dynamo namespace for --install-dynamo (default: dynamo-system).

  Same as: NEMOCLAW_NAMESPACE, DYNAMO_NAMESPACE.

Optional environment variables:
  DYNAMO_DEPLOY_MANIFEST   Path to Dynamo deploy.yaml for --install-dynamo
                           (default: dynamo/dynamo/recipes/nemotron-3-super-fp8/
                           sglang/disagg/deploy.yaml under this workshop).
  DYNAMO_READY_POLL_INTERVAL   Seconds between status checks while waiting (default: 15).
  DYNAMO_READY_TIMEOUT_SEC     Max seconds to wait for pods (0 = no limit; default: 3600).
  DYNAMO_DISAGG_MIN_PODS       Minimum ready pods per disagg tier (default: 3).
  NEMOCLAW_GIT_URL             Clone URL for NemoClaw (default: https://github.com/NVIDIA/NemoClaw.git).
                               Sources are placed at nemoclaw-base/nemoclaw-src/NemoClaw/.
  NEMOCLAW_GIT_TAG             Git tag to fetch and check out (default: v0.0.18). If unset,
                               NEMOCLAW_GIT_REF is used for backward compatibility.
  VERBOSE                      Set to 1 for extra messages (stream docker push, kubectl delete
                               detail, full paths, Dynamo criteria).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --acr-name)
      [[ $# -ge 2 ]] || {
        log "Missing value for --acr-name"
        exit 1
      }
      ACR_NAME="$2"
      shift 2
      ;;
    --nemoclaw-namespace)
      [[ $# -ge 2 ]] || {
        log "Missing value for --nemoclaw-namespace"
        exit 1
      }
      NEMOCLAW_NAMESPACE="$2"
      shift 2
      ;;
    --dynamo-namespace)
      [[ $# -ge 2 ]] || {
        log "Missing value for --dynamo-namespace"
        exit 1
      }
      DYNAMO_NAMESPACE="$2"
      shift 2
      ;;
    --install-dynamo)
      INSTALL_DYNAMO=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log "Unknown option: $1"
      usage >&2
      exit 1
      ;;
  esac
done

NEMOCLAW_NAMESPACE="${NEMOCLAW_NAMESPACE:-nemoclaw}"
DYNAMO_NAMESPACE="${DYNAMO_NAMESPACE:-dynamo-system}"

require_non_empty() {
  local var_name="$1"
  local value="$2"
  local flag_hint="$3"
  [[ -n "${value}" ]] || {
    log "Missing required ${var_name} (${flag_hint} or environment variable)."
    return 1
  }
  return 0
}

missing_required=0
require_non_empty "ACR_NAME" "${ACR_NAME}" "--acr-name" || missing_required=1
if [[ "${missing_required}" -ne 0 ]]; then
  usage >&2
  exit 1
fi

IMAGE="${ACR_NAME}.azurecr.io/nemoclaw-dind-src:latest"

is_push_auth_failure() {
  local file="$1"
  grep -qiE \
    'unauthorized|authentication required|401: Unauthorized|no basic auth credentials|error getting credentials|denied: requested access to the resource is denied' \
    "$file"
}

push_with_acr_retry() {
  local err rc
  err="$(mktemp)"
  trap 'rm -f "${err}"' RETURN

  if [[ "${VERBOSE}" == "1" ]]; then
    set +e
    docker push "${IMAGE}" 2>&1 | tee "${err}"
    rc=${PIPESTATUS[0]}
    set -e
  else
    set +e
    docker push "${IMAGE}" &>"${err}"
    rc=$?
    set -e
  fi

  if [[ "${rc}" -eq 0 ]]; then
    return 0
  fi

  printf '%s%s%s\n' "${_E}" "Docker push failed (exit ${rc})." "${_R}" >&2
  if [[ "${VERBOSE}" != "1" ]]; then
    printf '%s\n' "Output:" >&2
    cat "${err}" >&2
  fi

  if is_push_auth_failure "${err}"; then
    printf '%s%s%s\n' "${_Y}" "Registry auth issue — running az acr login, then retrying push." "${_R}" >&2
    log_verbose "az acr login --name ${ACR_NAME}"
    az acr login --name "${ACR_NAME}"

    if [[ "${VERBOSE}" == "1" ]]; then
      set +e
      docker push "${IMAGE}" 2>&1 | tee "${err}"
      rc=${PIPESTATUS[0]}
      set -e
    else
      set +e
      docker push "${IMAGE}" &>"${err}"
      rc=$?
      set -e
    fi

    if [[ "${rc}" -eq 0 ]]; then
      return 0
    fi
    printf '%s%s%s\n' "${_E}" "Docker push failed after az acr login (exit ${rc})." "${_R}" >&2
    if [[ "${VERBOSE}" != "1" ]]; then
      printf '%s\n' "Output:" >&2
      cat "${err}" >&2
    fi
    return "${rc}"
  fi

  printf '%s%s%s\n' "${_E}" "Output did not match known auth errors; not retrying." "${_R}" >&2
  return "${rc}"
}

# Count Running pods whose READY is N/N (all containers ready) and name contains needle.
dynamo_count_ready_matching() {
  local ns="$1"
  local needle="$2"
  local n=0
  local name ready status
  while read -r name ready status _; do
    [[ -n "${name}" ]] || continue
    [[ "${name}" == *"${needle}"* ]] || continue
    [[ "${status}" == "Running" ]] || continue
    if [[ "${ready}" =~ ^([0-9]+)/([0-9]+)$ ]] && [[ "${BASH_REMATCH[1]}" -eq "${BASH_REMATCH[2]}" ]]; then
      ((n += 1)) || true
    fi
  done < <(kubectl get pods -n "${ns}" --no-headers 2>/dev/null || true)
  printf '%s' "${n}"
}

# True when every pod in ns is Running and READY is N/N.
dynamo_all_pods_running_ready() {
  local ns="$1"
  local out
  if ! out="$(kubectl get pods -n "${ns}" --no-headers 2>/dev/null)"; then
    return 1
  fi
  [[ -n "${out}" ]] || return 1
  local name ready status
  while read -r name ready status _; do
    [[ -n "${name}" ]] || continue
    [[ "${status}" == "Running" ]] || return 1
    if [[ ! "${ready}" =~ ^([0-9]+)/([0-9]+)$ ]] || [[ "${BASH_REMATCH[1]}" -ne "${BASH_REMATCH[2]}" ]]; then
      return 1
    fi
  done <<<"${out}"
  return 0
}

wait_for_dynamo_pods_ready() {
  local ns="${DYNAMO_NAMESPACE}"
  local interval="${DYNAMO_READY_POLL_INTERVAL}"
  local max_wait="${DYNAMO_READY_TIMEOUT_SEC}"
  local min_each="${DYNAMO_DISAGG_MIN_PODS}"
  local start now elapsed
  local dynamo_block_lines=0
  local block pods
  start="$(date +%s)"

  log_verbose "Criteria: every pod Running/Ready; ≥${min_each} ready per tier (*-disagg-decode-*, *-disagg-frontend-*, *-disagg-prefill-*)."
  if [[ ! -t 2 ]]; then
    printf '%s%s%s\n' "${_D}" "Dynamo: polling pods every ${interval}s (timeout ${max_wait}s, 0 = none)…" "${_R}" >&2
  fi

  while true; do
    now="$(date +%s)"
    elapsed=$((now - start))

    local c_decode c_frontend c_prefill
    c_decode="$(dynamo_count_ready_matching "${ns}" "-disagg-decode-")"
    c_frontend="$(dynamo_count_ready_matching "${ns}" "-disagg-frontend-")"
    c_prefill="$(dynamo_count_ready_matching "${ns}" "-disagg-prefill-")"

    pods="$(kubectl get pods -n "${ns}" -o wide 2>&1)" || true
    block="kubectl get pods -n ${ns} -o wide  (decode-ready=${c_decode}/${min_each} frontend-ready=${c_frontend}/${min_each} prefill-ready=${c_prefill}/${min_each}  elapsed=${elapsed}s)
${pods}"

    if [[ -t 2 ]] && [[ "${dynamo_block_lines}" -gt 0 ]]; then
      printf '\033[%dA\033[J' "${dynamo_block_lines}" >&2
    fi
    printf '%s\n' "${block}" >&2
    if [[ -t 2 ]]; then
      dynamo_block_lines="$(printf '%s\n' "${block}" | wc -l | tr -d '[:space:]')"
    else
      dynamo_block_lines=0
    fi

    if [[ "${c_decode}" -ge "${min_each}" && "${c_frontend}" -ge "${min_each}" && "${c_prefill}" -ge "${min_each}" ]] &&
      dynamo_all_pods_running_ready "${ns}"; then
      printf '\n' >&2
      section_end_ok "Dynamo workloads ready (namespace ${ns})"
      return 0
    fi

    if [[ "${max_wait}" -gt 0 && "${elapsed}" -ge "${max_wait}" ]]; then
      printf '\n' >&2
      section_end_err "Timed out after ${max_wait}s waiting for Dynamo pods in ${ns}"
      exit 1
    fi

    sleep "${interval}"
  done
}

install_dynamo() {
  [[ -f "${DYNAMO_DEPLOY_MANIFEST}" ]] || {
    log "Missing Dynamo manifest: ${DYNAMO_DEPLOY_MANIFEST}"
    exit 1
  }
  section "DYNAMO" "apply + pod wait · ns ${DYNAMO_NAMESPACE} · $(basename "${DYNAMO_DEPLOY_MANIFEST}") · poll ${DYNAMO_READY_POLL_INTERVAL}s · timeout ${DYNAMO_READY_TIMEOUT_SEC}s"
  log_verbose "${DYNAMO_DEPLOY_MANIFEST}"
  if [[ "${VERBOSE}" == "1" ]]; then
    kubectl delete -f "${DYNAMO_DEPLOY_MANIFEST}" -n "${DYNAMO_NAMESPACE}" --ignore-not-found >&2
  else
    kubectl delete -f "${DYNAMO_DEPLOY_MANIFEST}" -n "${DYNAMO_NAMESPACE}" --ignore-not-found &>/dev/null
  fi
  kubectl apply -f "${DYNAMO_DEPLOY_MANIFEST}" -n "${DYNAMO_NAMESPACE}"
  wait_for_dynamo_pods_ready
}

# Clone NVIDIA/NemoClaw at NEMOCLAW_GIT_TAG into nemoclaw-base/nemoclaw-src/NemoClaw (docker build context).
# Only ${NEMOCLAW_REPO_DIR} is replaced; other files under nemoclaw-src are left as-is.
ensure_nemoclaw_src() {
  command -v git >/dev/null 2>&1 || {
    log "git is required to clone NemoClaw into ${NEMOCLAW_REPO_DIR}"
    exit 1
  }
  mkdir -p "${NEMOCLAW_SRC}"

  local tag_at_head=""
  if [[ -d "${NEMOCLAW_REPO_DIR}/.git" ]]; then
    tag_at_head="$(git -C "${NEMOCLAW_REPO_DIR}" describe --tags --exact-match HEAD 2>/dev/null || true)"
    if [[ "${tag_at_head}" == "${NEMOCLAW_GIT_TAG}" ]]; then
      log_verbose "NemoClaw already at tag ${NEMOCLAW_GIT_TAG}: ${NEMOCLAW_REPO_DIR}"
      return 0
    fi
  fi

  rm -rf "${NEMOCLAW_REPO_DIR}"
  printf '%s%s%s\n' "${_D}" "Cloning NemoClaw tag ${NEMOCLAW_GIT_TAG} from ${NEMOCLAW_GIT_URL} → ${NEMOCLAW_REPO_DIR}" "${_R}" >&2
  git init "${NEMOCLAW_REPO_DIR}"
  git -C "${NEMOCLAW_REPO_DIR}" remote add origin "${NEMOCLAW_GIT_URL}"
  GIT_TERMINAL_PROMPT=0 git -C "${NEMOCLAW_REPO_DIR}" fetch --depth 1 origin "refs/tags/${NEMOCLAW_GIT_TAG}:refs/tags/${NEMOCLAW_GIT_TAG}"
  git -C "${NEMOCLAW_REPO_DIR}" -c advice.detachedHead=false checkout --detach "${NEMOCLAW_GIT_TAG}"
}

[[ -d "${BASE_DIR}" ]] || { log "Missing directory: ${BASE_DIR}"; exit 1; }
[[ -d "${INSTALL_DIR}" ]] || { log "Missing directory: ${INSTALL_DIR}"; exit 1; }
[[ -f "${INSTALL_DIR}/nemoclaw-k8s.yaml" ]] || { log "Missing file: ${INSTALL_DIR}/nemoclaw-k8s.yaml"; exit 1; }

if [[ "${INSTALL_DYNAMO}" -eq 1 ]]; then
  install_dynamo
fi

ensure_nemoclaw_src

section "DOCKER BUILD" "${IMAGE}"
if ! (
  cd "${BASE_DIR}"
  docker build --platform linux/amd64 -t "${IMAGE}" .
); then
  section_end_err "Docker build failed"
  exit 1
fi
section_end_ok "Docker build finished"

section "DOCKER PUSH" "${IMAGE}"
if ! push_with_acr_retry; then
  section_end_err "Docker push failed"
  exit 1
fi
section_end_ok "Docker push finished"

section "KUBERNETES · NEMOCLAW" "namespace ${NEMOCLAW_NAMESPACE}"
(
  cd "${INSTALL_DIR}"
  if [[ -f ./nemoclaw-secrets.yaml ]]; then
    kubectl apply -f ./nemoclaw-secrets.yaml -n "${NEMOCLAW_NAMESPACE}"
    log_verbose "Applied ./nemoclaw-secrets.yaml"
  else
    printf '%s%s%s\n' "${_Y}" "No ./nemoclaw-secrets.yaml — add it (see nemoclaw-secrets.example.yaml) for Azure OpenAI keys." "${_R}" >&2
  fi
  kubectl delete pod nemoclaw -n "${NEMOCLAW_NAMESPACE}" --ignore-not-found
  # Substitute registry from ACR_NAME; edit CHAT_UI_URL / Azure URLs in nemoclaw-k8s.yaml separately.
  sed "s|anslutskynemoclawclusterregistry.azurecr.io|${ACR_NAME}.azurecr.io|g" ./nemoclaw-k8s.yaml | kubectl apply -f - -n "${NEMOCLAW_NAMESPACE}"
)
section_end_ok "NemoClaw install refreshed"

printf '%s%s%s\n' "${_D}" "Finished · ${IMAGE}" "${_R}" >&2
