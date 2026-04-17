#!/usr/bin/env bash
# Populate Docker2/ with nemoclaw/, nemoclaw-blueprint/, and scripts/ from a NemoClaw
# checkout (./NemoClaw, ../NemoClaw, or NEMOCLAW_REPO_PATH). Upstream URL: nemoclaw-upstream.url.
# so `nemoclaw onboard --from ./Dockerfile` has a valid build context (onboard copies
# only the directory containing the Dockerfile).
#
# Kubernetes (nemoclaw-dind-src workspace container): set NEMOCLAW_K8S_WORKSPACE=1
# and run this script; it installs tooling, bridges Dynamo via socat, waits for Docker,
# and builds/installs openshell-cli. Provider/model env vars come from the pod spec.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Canonical upstream (see nemoclaw-upstream.url). Override with NEMOCLAW_GIT_URL.
NEMOCLAW_GIT_URL="${NEMOCLAW_GIT_URL:-}"
if [[ -z "$NEMOCLAW_GIT_URL" && -f "$HERE/nemoclaw-upstream.url" ]]; then
  NEMOCLAW_GIT_URL="$(tr -d '[:space:]' <"$HERE/nemoclaw-upstream.url")"
fi
NEMOCLAW_GIT_URL="${NEMOCLAW_GIT_URL:-https://github.com/NVIDIA/NemoClaw.git}"

k8s_workspace_bootstrap() {
  echo "[1/4] !!!!!!!!!!!!!!!!!!!!!!!!!!!!! Installing packages... !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! "
  apt-get update -qq
  apt-get install -y -qq docker.io socat curl >/dev/null 2>&1

  echo "[2/4] Starting socat proxy..."
  socat TCP-LISTEN:8000,fork,reuseaddr TCP:"${DYNAMO_HOST:?DYNAMO_HOST must be set}" &
  echo "127.0.0.1 host.openshell.internal" >> /etc/hosts
  sleep 1

  echo "[3/4] Waiting for Docker daemon..."
  for _ in $(seq 1 30); do
    if docker info >/dev/null 2>&1; then break; fi
    sleep 2
  done
  docker info >/dev/null 2>&1 || { echo "Docker not ready"; exit 1; }
  echo "Docker ready"

  echo "[4/4] Running NemoClaw workspace setup..."
  NEMOCLAW_SRC="${NEMOCLAW_SRC:-/nemoclaw-src}"
  echo "NEMOCLAW_SRC: $NEMOCLAW_SRC"
  ls -la "$NEMOCLAW_SRC"

  # source "$HOME/.cargo/env"

  # cd /openshell-src
  # cargo build -p openshell-cli --release
  # install -m 755 /openshell-src/target/release/openshell "/usr/local/bin/openshell"

  export NEMOCLAW_DISABLE_DEVICE_AUTH=1

  # echo "Installing NemoClaw..."
  # "$NEMOCLAW_SRC/scripts/install.sh"

  echo "Onboard complete. Container staying alive."
  exec sleep infinity
}

if [[ "${NEMOCLAW_K8S_WORKSPACE:-}" == "1" ]]; then
  k8s_workspace_bootstrap
  echo "error: K8s workspace bootstrap returned without exec" >&2
  exit 1
fi

resolve_nemoclaw_repo() {
  if [[ -n "${NEMOCLAW_REPO_PATH:-}" ]]; then
    local repo
    repo="$(cd "$NEMOCLAW_REPO_PATH" && pwd)"
    if [[ -d "$repo/nemoclaw" && -d "$repo/nemoclaw-blueprint" && -d "$repo/scripts" ]]; then
      printf '%s\n' "$repo"
      return 0
    fi
    return 1
  fi
  for candidate in "$HERE/NemoClaw" "$HERE/../NemoClaw"; do
    if [[ -d "$candidate/nemoclaw" && -d "$candidate/nemoclaw-blueprint" && -d "$candidate/scripts" ]]; then
      (cd "$candidate" && pwd)
      return
    fi
  done
  return 1
}

if ! NEMOCLAW_REPO="$(resolve_nemoclaw_repo)"; then
  echo "error: no NemoClaw checkout found (need nemoclaw/, nemoclaw-blueprint/, scripts/)." >&2
  echo "  Set NEMOCLAW_REPO_PATH, or clone from ${NEMOCLAW_GIT_URL} next to this directory, e.g." >&2
  echo "    git clone ${NEMOCLAW_GIT_URL} \"$(cd "$HERE/.." && pwd)/NemoClaw\"" >&2
  exit 1
fi

echo "NEMOCLAW_REPO: $NEMOCLAW_REPO"

ls -la "$NEMOCLAW_REPO"
for name in nemoclaw nemoclaw-blueprint scripts; do
  rm -rf "$HERE/$name"
  cp -R "$NEMOCLAW_REPO/$name" "$HERE/$name"
done
rm -rf "$HERE/nemoclaw/node_modules" "$HERE/nemoclaw-blueprint/.venv" 2>/dev/null || true
# Docker2 network policy (wide HTTPS egress for curl/node in sandboxes). Required so
# `openshell sandbox create --policy` matches the image when using NEMOCLAW_FROM_DOCKERFILE.
mkdir -p "$HERE/nemoclaw-blueprint/policies"
POLICY_SRC=""
if [[ -f "$HERE/policy-overrides/openclaw-sandbox.yaml" ]]; then
  POLICY_SRC="$HERE/policy-overrides/openclaw-sandbox.yaml"
elif [[ -f "$NEMOCLAW_REPO/Docker2/policy-overrides/openclaw-sandbox.yaml" ]]; then
  POLICY_SRC="$NEMOCLAW_REPO/Docker2/policy-overrides/openclaw-sandbox.yaml"
fi
if [[ -n "$POLICY_SRC" ]]; then
  cp "$POLICY_SRC" "$HERE/nemoclaw-blueprint/policies/openclaw-sandbox.yaml"
  echo "Applied Docker2 openclaw-sandbox policy from $POLICY_SRC"
else
  echo "warning: no Docker2 policy override found (expected policy-overrides/openclaw-sandbox.yaml or" \
    "NemoClaw Docker2/policy-overrides/). Sandbox curl egress may be denied (CONNECT 403)." >&2
fi
echo "Docker2 build context ready (from $NEMOCLAW_REPO)."
