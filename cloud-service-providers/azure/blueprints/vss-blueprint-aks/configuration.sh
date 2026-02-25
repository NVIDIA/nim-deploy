#!/bin/bash

## Video Search and Summarization (VSS) — AKS Deployment Configuration Validation

echo "=============================================="
echo "  VSS Deployment Configuration Validation"
echo "=============================================="
echo ""
echo "You must have an NGC API key and a Hugging Face token."
echo "  NGC:          https://org.ngc.nvidia.com/setup/api-key"
echo "  Hugging Face: https://huggingface.co/settings/tokens"
echo "                Accept terms at https://huggingface.co/nvidia/Cosmos-Reason2-8B"
echo ""
echo "Checking environment variables..."
echo ""

function env_var_check() {
  local var_name="$1"
  local show_mode="$2"

  if [ -z "${!var_name}" ]; then
    echo "Error: $var_name is not set."
    exit 1
  fi

  if [ "$show_mode" = "show" ]; then
    echo "$var_name=${!var_name}"
  else
    local value="${!var_name}"
    echo "$var_name=${value:0:10}...<masked>"
  fi
}

echo "Checking required credentials..."
env_var_check NGC_API_KEY
env_var_check HF_TOKEN

echo ""
echo "Validating deployment environment..."

if ! az account show &>/dev/null; then
  echo "Error: Azure CLI is not logged in."
  echo "  Run: az login"
  exit 1
else
  AZURE_SUB=$(az account show --query name -o tsv)
  echo "Azure subscription: $AZURE_SUB"
fi

if ! kubectl cluster-info &>/dev/null; then
  echo "Error: kubectl is not configured or cluster is unreachable."
  echo "  Run: az aks get-credentials --resource-group <rg> --name <cluster>"
  exit 1
else
  echo "kubectl context OK"
fi

if ! command -v helm &>/dev/null; then
  echo "Error: helm is not installed."
  exit 1
else
  echo "helm OK"
fi

echo ""
echo "=============================================="
echo "  Configuration validation complete!"
echo "=============================================="
echo ""
echo "Ready to proceed with deployment."
echo ""
