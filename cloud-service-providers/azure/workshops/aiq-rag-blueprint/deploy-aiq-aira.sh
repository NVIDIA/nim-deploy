#!/usr/bin/env bash
# shfmt -i 2 -ci -w
set -Eo pipefail

trap exit SIGINT SIGTERM

################################################################################
# AIQ AIRA Blueprint Deployment Script
# Deploys NVIDIA AIQ AIRA Research Assistant on AKS with RAG integration

################################################################################
# Default configuration
# AKS Infrastructure
REGION=${REGION:-eastus}
RESOURCE_GROUP=${RESOURCE_GROUP:-rg-aiq-demo}
CLUSTER_NAME=${CLUSTER_NAME:-aks-aiq-demo}
CLUSTER_MACHINE_TYPE=${CLUSTER_MACHINE_TYPE:-Standard_D32s_v5}
NODE_POOL_MACHINE_TYPE=${NODE_POOL_MACHINE_TYPE:-standard_nc96ads_a100_v4}
NODE_COUNT=${NODE_COUNT:-1}
CPU_COUNT=${CPU_COUNT:-2}

# AIQ Configuration
NAMESPACE=${NAMESPACE:-aira}
RAG_NAMESPACE=${RAG_NAMESPACE:-rag}
CHART_VERSION=${CHART_VERSION:-v1.2.0}
RAG_CHART_VERSION=${RAG_CHART_VERSION:-v2.3.0}
NGC_API_KEY=${NGC_API_KEY:-}
NVIDIA_API_KEY=${NVIDIA_API_KEY:-}
NVIDIA_API_URL=${NVIDIA_API_URL:-https://integrate.api.nvidia.com}
TAVILY_API_KEY=${TAVILY_API_KEY:-}
MODEL_NAME=${MODEL_NAME:-nvidia/llama-3.3-nemotron-super-49b-v1.5}
PHOENIX_ENABLED=${PHOENIX_ENABLED:-true}
RAG_SERVER_URL=${RAG_SERVER_URL:-http://rag-server.rag.svc.cluster.local:8081}
RAG_INGEST_URL=${RAG_INGEST_URL:-http://ingestor-server.rag.svc.cluster.local:8082}
MILVUS_HOST=${MILVUS_HOST:-milvus.rag.svc.cluster.local}
MILVUS_PORT=${MILVUS_PORT:-19530}
################################################################################

__usage="
    -x  action to be executed.

Possible verbs are:
    Infrastructure Setup:
    setup-infra    Create AKS cluster and GPU node pool.
    install-gpu    Install NVIDIA GPU Operator.
    install-rag    Deploy RAG 2.3 blueprint.

    AIQ Deployment:
    install        Deploy AIQ AIRA blueprint with all components.
    upgrade        Upgrade existing AIQ AIRA deployment.
    delete         Delete AIQ AIRA deployment.
    show           Show deployment information and status.
    expose         Expose frontend service with LoadBalancer.
    logs           Show backend logs.

    Utilities:
    check-deps     Check required dependencies.
    validate       Validate configuration and API keys.
    full-setup     Complete setup: infra + GPU + RAG + AIQ.

Environment variables (with defaults):
    AKS Infrastructure:
    REGION=${REGION}
    RESOURCE_GROUP=${RESOURCE_GROUP}
    CLUSTER_NAME=${CLUSTER_NAME}
    CLUSTER_MACHINE_TYPE=${CLUSTER_MACHINE_TYPE}
    NODE_POOL_MACHINE_TYPE=${NODE_POOL_MACHINE_TYPE}
    NODE_COUNT=${NODE_COUNT}
    CPU_COUNT=${CPU_COUNT}

    AIQ Configuration:
    NAMESPACE=${NAMESPACE}
    RAG_NAMESPACE=${RAG_NAMESPACE}
    CHART_VERSION=${CHART_VERSION}
    RAG_CHART_VERSION=${RAG_CHART_VERSION}
    NGC_API_KEY=${NGC_API_KEY:+***set***}
    NVIDIA_API_KEY=${NVIDIA_API_KEY:+***set***}
    NVIDIA_API_URL=${NVIDIA_API_URL}
    TAVILY_API_KEY=${TAVILY_API_KEY:+***set***}
    MODEL_NAME=${MODEL_NAME}
    PHOENIX_ENABLED=${PHOENIX_ENABLED}
    RAG_SERVER_URL=${RAG_SERVER_URL}
    RAG_INGEST_URL=${RAG_INGEST_URL}
    MILVUS_HOST=${MILVUS_HOST}
    MILVUS_PORT=${MILVUS_PORT}
"

usage() {
  echo "usage: ${0##*/} [options]"
  echo "${__usage/[[:space:]]/}"
  exit 1
}

print_header() {
  echo ""
  echo "AIQ AIRA Blueprint Deployment"
  echo "=========================================="
  echo ""
  echo "AKS Infrastructure:"
  echo "  Region:             $REGION"
  echo "  Resource Group:     $RESOURCE_GROUP"
  echo "  Cluster:            $CLUSTER_NAME"
  echo "  GPU Node Type:      $NODE_POOL_MACHINE_TYPE"
  echo "  GPU Node Count:     $NODE_COUNT"
  echo ""
  echo "AIQ Configuration:"
  echo "  Namespace:          $NAMESPACE"
  echo "  Chart Version:      $CHART_VERSION"
  echo "  Model:              $MODEL_NAME"
  echo "  API URL:            $NVIDIA_API_URL"
  echo "  Phoenix:            $PHOENIX_ENABLED"
  echo "  RAG Server:         $RAG_SERVER_URL"
  echo "  Milvus:             $MILVUS_HOST:$MILVUS_PORT"
  echo ""
}

log() {
  echo "[$(date +"%r")] $*"
}

check_dependencies() {
  log "Checking dependencies..."
  local _NEEDED="az kubectl helm"
  local _DEP_FLAG=false

  for i in ${_NEEDED}; do
    if hash "$i" 2>/dev/null; then
      log "  $i: OK"
    else
      log "  $i: NOT FOUND"
      _DEP_FLAG=true
    fi
  done

  if [[ "${_DEP_FLAG}" == "true" ]]; then
    log "Dependencies missing. Please install them before proceeding"
    exit 1
  fi

  log "All dependencies satisfied"
}

validate_config() {
  log "Validating configuration..."
  local _ERROR=false

  if [[ -z "${NGC_API_KEY}" ]]; then
    log "  NGC_API_KEY: NOT SET"
    _ERROR=true
  else
    log "  NGC_API_KEY: OK (length: ${#NGC_API_KEY})"
  fi

  if [[ -z "${NVIDIA_API_KEY}" ]]; then
    log "  NVIDIA_API_KEY: NOT SET"
    _ERROR=true
  else
    log "  NVIDIA_API_KEY: OK (length: ${#NVIDIA_API_KEY})"
  fi

  if [[ -z "${TAVILY_API_KEY}" ]]; then
    log "  TAVILY_API_KEY: NOT SET"
    _ERROR=true
  else
    log "  TAVILY_API_KEY: OK (length: ${#TAVILY_API_KEY})"
  fi

  # Check if RAG namespace exists
  if kubectl get namespace "$RAG_NAMESPACE" >/dev/null 2>&1; then
    log "  RAG namespace: OK"
  else
    log "  RAG namespace: NOT FOUND (expected: $RAG_NAMESPACE)"
    log "  Please deploy RAG blueprint first"
    _ERROR=true
  fi

  if [[ "${_ERROR}" == "true" ]]; then
    log "Configuration validation failed"
    exit 1
  fi

  log "Configuration validation passed"
}

check_rag_services() {
  log "Checking RAG services availability..."

  local _SERVICES=(
    "rag-server"
    "ingestor-server"
    "milvus"
  )

  for service in "${_SERVICES[@]}"; do
    if kubectl get service "$service" -n "$RAG_NAMESPACE" >/dev/null 2>&1; then
      log "  $service: OK"
    else
      log "  $service: NOT FOUND in namespace $RAG_NAMESPACE"
      log "  RAG blueprint may not be deployed correctly"
    fi
  done
}

create_resource_group() {
  log "Creating resource group $RESOURCE_GROUP in $REGION..."

  if az group show --name "$RESOURCE_GROUP" >/dev/null 2>&1; then
    log "Resource group already exists"
  else
    az group create -l "$REGION" -n "$RESOURCE_GROUP"
    log "Resource group created successfully"
  fi
}

create_aks_cluster() {
  log "Creating AKS cluster $CLUSTER_NAME..."

  if az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" >/dev/null 2>&1; then
    log "AKS cluster already exists"
  else
    log "This will take 5-10 minutes..."
    az aks create -g "$RESOURCE_GROUP" \
      -n "$CLUSTER_NAME" \
      --location "$REGION" \
      --node-count "$CPU_COUNT" \
      --node-vm-size "$CLUSTER_MACHINE_TYPE" \
      --enable-node-public-ip \
      --generate-ssh-keys

    log "AKS cluster created successfully"
  fi
}

get_aks_credentials() {
  log "Getting AKS cluster credentials..."
  az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing
  log "Credentials configured"
}

create_gpu_nodepool() {
  log "Creating GPU node pool..."

  if az aks nodepool show --resource-group "$RESOURCE_GROUP" \
    --cluster-name "$CLUSTER_NAME" \
    --name gpupool >/dev/null 2>&1; then
    log "GPU node pool already exists"
  else
    log "This will take 5-10 minutes..."
    az aks nodepool add --resource-group "$RESOURCE_GROUP" \
      --cluster-name "$CLUSTER_NAME" \
      --name gpupool \
      --node-count "$NODE_COUNT" \
      --gpu-driver none \
      --node-vm-size "$NODE_POOL_MACHINE_TYPE" \
      --node-osdisk-size 2048 \
      --max-pods 110

    log "GPU node pool created successfully"
  fi
}

install_gpu_operator() {
  log "Installing NVIDIA GPU Operator..."

  # Add NVIDIA Helm repo
  log "Adding NVIDIA Helm repository..."
  helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --pass-credentials
  helm repo update

  # Check if already installed
  if helm list -n gpu-operator 2>/dev/null | grep -q gpu-operator; then
    log "GPU Operator already installed"
  else
    log "This will take 3-5 minutes..."
    helm install --create-namespace \
      --namespace gpu-operator \
      nvidia/gpu-operator \
      --wait \
      --generate-name

    log "GPU Operator installed successfully"
  fi
}

validate_gpu_operator() {
  log "Validating GPU Operator installation..."
  log "Waiting for all pods to be ready..."

  local MAX_WAIT=300
  local ELAPSED=0

  while [ $ELAPSED -lt $MAX_WAIT ]; do
    local NOT_READY=$(kubectl get pods -n gpu-operator --no-headers 2>/dev/null | grep -v "Running" | grep -v "Completed" | wc -l)
    if [ "$NOT_READY" -eq 0 ]; then
      log "All GPU Operator pods are ready"
      kubectl get pods -n gpu-operator
      return 0
    fi
    sleep 10
    ELAPSED=$((ELAPSED + 10))
    log "  Waiting... ($ELAPSED/$MAX_WAIT seconds)"
  done

  log "Timeout waiting for GPU Operator pods"
  kubectl get pods -n gpu-operator
  return 1
}

download_rag_values() {
  log "Downloading RAG values file..."
  if [ ! -f "values.yaml" ]; then
    wget -O values.yaml https://tinyurl.com/rag23values
    log "Values file downloaded"
  else
    log "Values file already exists"
  fi
}

install_rag_blueprint() {
  log "Installing RAG 2.3 Blueprint..."

  if helm list -n "$RAG_NAMESPACE" 2>/dev/null | grep -q rag; then
    log "RAG Blueprint already installed"
  else
    log "This will take 15-20 minutes..."
    helm upgrade --install rag \
      --create-namespace -n "$RAG_NAMESPACE" \
      "https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-rag-${RAG_CHART_VERSION}.tgz" \
      --username '$oauthtoken' \
      --password "${NGC_API_KEY}" \
      --values values.yaml \
      --set nim-llm.enabled=true \
      --set nvidia-nim-llama-32-nv-embedqa-1b-v2.enabled=true \
      --set nvidia-nim-llama-32-nv-rerankqa-1b-v2.enabled=true \
      --set ingestor-server.enabled=true \
      --set nv-ingest.enabled=true \
      --set nv-ingest.nemoretriever-page-elements-v2.deployed=true \
      --set nv-ingest.nemoretriever-graphic-elements-v1.deployed=false \
      --set nv-ingest.nemoretriever-table-structure-v1.deployed=true \
      --set nv-ingest.paddleocr-nim.deployed=false \
      --set imagePullSecret.password="${NGC_API_KEY}" \
      --set ngcApiSecret.password="${NGC_API_KEY}"

    log "RAG Blueprint installed successfully"
  fi
}

wait_for_rag_deployment() {
  log "Waiting for RAG deployments to be ready..."
  log "This may take up to 20 minutes for all services to start..."

  local _KEY_DEPLOYMENTS=(
    "rag-server"
    "ingestor-server"
    "milvus-standalone"
  )

  for deployment in "${_KEY_DEPLOYMENTS[@]}"; do
    log "  Checking $deployment..."
    if kubectl get deployment "$deployment" -n "$RAG_NAMESPACE" >/dev/null 2>&1; then
      kubectl rollout status deployment/"$deployment" -n "$RAG_NAMESPACE" --timeout=20m || true
    else
      log "  $deployment not found, skipping..."
    fi
  done

  log "RAG deployment status:"
  kubectl get pods -n "$RAG_NAMESPACE"
}

helm_install() {
  log "Installing AIQ AIRA blueprint..."

  helm install aiq \
    -n "$NAMESPACE" \
    "https://helm.ngc.nvidia.com/nvidia/blueprint/charts/aiq-aira-${CHART_VERSION}.tgz" \
    --create-namespace \
    --username '$oauthtoken' \
    --password "${NGC_API_KEY}" \
    --set phoenix.enabled="${PHOENIX_ENABLED}" \
    --set phoenix.image.repository=docker.io/arizephoenix/phoenix \
    --set phoenix.image.tag=latest \
    --set tavilyApiSecret.password="${TAVILY_API_KEY}" \
    --set ngcApiSecret.password="${NVIDIA_API_KEY}" \
    --set nim-llm.enabled=true \
    --set config.rag_url="${RAG_SERVER_URL}" \
    --set config.rag_ingest_url="${RAG_INGEST_URL}" \
    --set config.milvus_host="${MILVUS_HOST}" \
    --set config.milvus_port="${MILVUS_PORT}" \
    --set backendEnvVars.INSTRUCT_BASE_URL="${NVIDIA_API_URL}" \
    --set backendEnvVars.INSTRUCT_MODEL_NAME="${MODEL_NAME}" \
    --set backendEnvVars.NEMOTRON_BASE_URL="${NVIDIA_API_URL}" \
    --set backendEnvVars.NEMOTRON_API_KEY="${NVIDIA_API_KEY}" \
    --set backendEnvVars.NEMOTRON_MODEL_NAME="${MODEL_NAME}"

  if [ $? -eq 0 ]; then
    log "AIQ AIRA installed successfully"
  else
    log "Installation failed"
    exit 1
  fi
}

helm_upgrade() {
  log "Upgrading AIQ AIRA deployment..."

  if ! helm list -n "$NAMESPACE" | grep -q "aiq"; then
    log "AIQ AIRA not found, please install first"
    exit 1
  fi

  helm upgrade aiq \
    -n "$NAMESPACE" \
    "https://helm.ngc.nvidia.com/nvidia/blueprint/charts/aiq-aira-${CHART_VERSION}.tgz" \
    --username '$oauthtoken' \
    --password "${NGC_API_KEY}" \
    --set phoenix.enabled="${PHOENIX_ENABLED}" \
    --set phoenix.image.repository=docker.io/arizephoenix/phoenix \
    --set phoenix.image.tag=latest \
    --set tavilyApiSecret.password="${TAVILY_API_KEY}" \
    --set ngcApiSecret.password="${NVIDIA_API_KEY}" \
    --set nim-llm.enabled=false \
    --set config.rag_url="${RAG_SERVER_URL}" \
    --set config.rag_ingest_url="${RAG_INGEST_URL}" \
    --set config.milvus_host="${MILVUS_HOST}" \
    --set config.milvus_port="${MILVUS_PORT}" \
    --set backendEnvVars.INSTRUCT_BASE_URL="${NVIDIA_API_URL}" \
    --set backendEnvVars.INSTRUCT_MODEL_NAME="${MODEL_NAME}" \
    --set backendEnvVars.NEMOTRON_BASE_URL="${NVIDIA_API_URL}" \
    --set backendEnvVars.NEMOTRON_API_KEY="${NVIDIA_API_KEY}" \
    --set backendEnvVars.NEMOTRON_MODEL_NAME="${MODEL_NAME}"

  if [ $? -eq 0 ]; then
    log "AIQ AIRA upgraded successfully"
  else
    log "Upgrade failed"
    exit 1
  fi
}

wait_for_deployment() {
  log "Waiting for deployments to be ready..."

  local _DEPLOYMENTS=(
    "aiq-aira-backend"
    "aiq-aira-frontend"
  )

  for deployment in "${_DEPLOYMENTS[@]}"; do
    log "  Waiting for $deployment..."
    if kubectl rollout status deployment/"$deployment" -n "$NAMESPACE" --timeout=5m; then
      log "  $deployment: READY"
    else
      log "  $deployment: TIMEOUT or FAILED"
      return 1
    fi
  done

  log "All deployments are ready"
}

do_install() {
  check_dependencies
  validate_config
  check_rag_services

  log ""
  log "Starting installation..."
  helm_install

  log ""
  wait_for_deployment

  log ""
  log "Installation completed!"
  log ""
  log "Next steps:"
  log "  1. Expose the frontend: $0 -x expose"
  log "  2. Check logs: $0 -x logs"
  log "  3. View status: $0 -x show"
}

do_upgrade() {
  check_dependencies
  validate_config

  log ""
  log "Starting upgrade..."
  helm_upgrade

  log ""
  wait_for_deployment

  log ""
  log "Upgrade completed!"
}

do_delete() {
  log "Deleting AIQ AIRA deployment..."

  if helm list -n "$NAMESPACE" | grep -q "aiq"; then
    helm uninstall aiq -n "$NAMESPACE"
    log "AIQ AIRA uninstalled"

    log "Deleting namespace $NAMESPACE..."
    kubectl delete namespace "$NAMESPACE" --wait=false

    log "Deletion initiated"
  else
    log "AIQ AIRA not found in namespace $NAMESPACE"
  fi
}

do_show() {
  log "Getting deployment information..."
  echo ""

  if helm list -n "$NAMESPACE" | grep -q "aiq"; then
    echo "Helm Release:"
    echo "============="
    helm list -n "$NAMESPACE" | grep aiq
    echo ""

    echo "Pods Status:"
    echo "============"
    kubectl get pods -n "$NAMESPACE"
    echo ""

    echo "Services:"
    echo "========="
    kubectl get svc -n "$NAMESPACE"
    echo ""

    # Check if LoadBalancer exists
    if kubectl get svc aiq-aira-frontend-lb -n "$NAMESPACE" >/dev/null 2>&1; then
      echo "Frontend LoadBalancer:"
      echo "======================"
      local EXTERNAL_IP=$(kubectl get svc aiq-aira-frontend-lb -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
      if [[ -n "$EXTERNAL_IP" ]]; then
        echo "Access the UI at: http://$EXTERNAL_IP"
      else
        echo "Waiting for external IP..."
        kubectl get svc aiq-aira-frontend-lb -n "$NAMESPACE"
      fi
      echo ""
    else
      echo "Frontend not exposed. Run: $0 -x expose"
      echo ""
    fi

    # Check backend pod environment
    local BACKEND_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=backend -o jsonpath='{.items[0].metadata.name}')
    if [[ -n "$BACKEND_POD" ]]; then
      echo "Backend Configuration:"
      echo "======================"
      kubectl exec -n "$NAMESPACE" "$BACKEND_POD" -- env | grep -E "^(INSTRUCT|NEMOTRON)_(BASE_URL|MODEL_NAME)=" | sort
      echo ""
    fi
  else
    log "AIQ AIRA not found in namespace $NAMESPACE"
    exit 1
  fi
}

do_expose() {
  log "Exposing frontend service..."

  if kubectl get svc aiq-aira-frontend-lb -n "$NAMESPACE" >/dev/null 2>&1; then
    log "LoadBalancer already exists"
    kubectl get svc aiq-aira-frontend-lb -n "$NAMESPACE"
  else
    kubectl expose deployment aiq-aira-frontend \
      -n "$NAMESPACE" \
      --name=aiq-aira-frontend-lb \
      --type=LoadBalancer \
      --port=80 \
      --target-port=3000

    log "LoadBalancer service created"
    log "Waiting for external IP assignment..."
    sleep 5

    kubectl get svc aiq-aira-frontend-lb -n "$NAMESPACE"

    log ""
    log "To get the external IP later, run: $0 -x show"
  fi
}

do_logs() {
  log "Getting backend logs..."
  echo ""

  local BACKEND_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=backend -o jsonpath='{.items[0].metadata.name}')

  if [[ -n "$BACKEND_POD" ]]; then
    echo "Logs from: $BACKEND_POD"
    echo "=========================================="
    kubectl logs -n "$NAMESPACE" "$BACKEND_POD" --tail=50
  else
    log "Backend pod not found"
    exit 1
  fi
}

do_validate() {
  check_dependencies
  validate_config
  check_rag_services

  log ""
  log "Validation completed successfully"
}

do_setup_infra() {
  log "Setting up AKS infrastructure..."
  log ""

  # Check Azure CLI
  if ! hash az 2>/dev/null; then
    log "Azure CLI not found. Please install it first."
    exit 1
  fi

  create_resource_group
  log ""

  create_aks_cluster
  log ""

  get_aks_credentials
  log ""

  create_gpu_nodepool
  log ""

  log "Infrastructure setup completed!"
  log ""
  log "Next steps:"
  log "  1. Install GPU Operator: $0 -x install-gpu"
  log "  2. Deploy RAG Blueprint: $0 -x install-rag"
  log "  3. Deploy AIQ: $0 -x install"
}

do_install_gpu() {
  check_dependencies

  log "Installing NVIDIA GPU Operator..."
  log ""

  install_gpu_operator
  log ""

  validate_gpu_operator
  log ""

  log "GPU Operator installation completed!"
  log ""
  log "Next step: Deploy RAG Blueprint with: $0 -x install-rag"
}

do_install_rag() {
  check_dependencies

  if [[ -z "${NGC_API_KEY}" ]]; then
    log "NGC_API_KEY not set. Please set it before deploying RAG."
    exit 1
  fi

  log "Installing RAG 2.3 Blueprint..."
  log ""

  download_rag_values
  log ""

  install_rag_blueprint
  log ""

  wait_for_rag_deployment
  log ""

  log "RAG Blueprint installation completed!"
  log ""
  log "Next step: Deploy AIQ with: $0 -x install"
}

do_full_setup() {
  log "Starting complete AIQ setup..."
  log ""

  log "=== Phase 1: Infrastructure Setup ==="
  do_setup_infra
  log ""

  log "=== Phase 2: GPU Operator Installation ==="
  do_install_gpu
  log ""

  log "=== Phase 3: RAG Blueprint Deployment ==="
  do_install_rag
  log ""

  log "=== Phase 4: AIQ AIRA Deployment ==="
  do_install
  log ""

  log "=================================================="
  log "Complete setup finished!"
  log "=================================================="
  log ""
  log "Final steps:"
  log "  1. Expose frontend: $0 -x expose"
  log "  2. View status: $0 -x show"
}

exec_case() {
  local _opt=$1

  case ${_opt} in
    setup-infra)   do_setup_infra ;;
    install-gpu)   do_install_gpu ;;
    install-rag)   do_install_rag ;;
    install)       do_install ;;
    upgrade)       do_upgrade ;;
    delete)        do_delete ;;
    show)          do_show ;;
    check-deps)    check_dependencies ;;
    expose)        do_expose ;;
    logs)          do_logs ;;
    validate)      do_validate ;;
    full-setup)    do_full_setup ;;
    *)             usage ;;
  esac
  unset _opt
}

################################################################################
# Entry point
main() {
  while getopts "x:" opt; do
    case $opt in
      x)
        exec_flag=true
        EXEC_OPT="${OPTARG}"
        ;;
      *) usage ;;
    esac
  done
  shift $((OPTIND - 1))

  if [ $OPTIND = 1 ]; then
    print_header
    usage
    exit 0
  fi

  # process actions
  if [[ "${exec_flag}" == "true" ]]; then
    exec_case "${EXEC_OPT}"
  fi
}

main "$@"
exit 0
