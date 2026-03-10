#!/bin/bash
set -euo pipefail

## Cosmos Dataset Search (CDS) — AKS Deployment Configuration Validation

echo "=============================================="
echo "  CDS Deployment Configuration Validation"
echo "=============================================="
echo ""
echo "You must have an NGC API key for pulling images and running NIM."
echo "Get your NGC API key at build.nvidia.com"
echo ""
echo "Checking environment variables..."
echo ""

function env_var_check() {
  local var_name="$1"
  local show_mode="$2"
  local optional="$3"

  if [ -z "${!var_name}" ]; then
    if [ "$optional" = "optional" ]; then
      echo "Warning: $var_name is not set (optional)"
      return 0
    else
      echo "Error: $var_name is not set."
      exit 1
    fi
  fi

  if [ "$show_mode" = "show" ]; then
    echo "$var_name=${!var_name}"
  else
    local value="${!var_name}"
    echo "$var_name=${value:0:10}...<masked>"
  fi
}

# Check required environment variables
echo "Checking required credentials..."
env_var_check NGC_API_KEY

echo ""
echo "Checking deployment configuration..."
env_var_check RESOURCE_GROUP show
env_var_check LOCATION show
env_var_check STORAGE_ACCOUNT_NAME show

echo ""
echo "Validating deployment environment..."

# Check Azure CLI is logged in
if ! az account show &>/dev/null; then
  echo "Error: Azure CLI is not logged in."
  echo "  Run: az login"
  exit 1
else
  AZURE_SUB=$(az account show --query name -o tsv)
  echo "Azure subscription: $AZURE_SUB"
fi

# Check kubectl context
if ! kubectl cluster-info &>/dev/null; then
  echo "Error: kubectl is not configured or cluster is unreachable."
  echo "  Run: az aks get-credentials --resource-group $RESOURCE_GROUP --name <cluster-name>"
  exit 1
else
  echo "kubectl context OK"
fi

# Check helm
if ! command -v helm &>/dev/null; then
  echo "Error: helm is not installed."
  exit 1
else
  echo "helm OK"
fi

# Validate storage account name format (3-24 lowercase alphanumeric)
if [[ ! "$STORAGE_ACCOUNT_NAME" =~ ^[a-z0-9]{3,24}$ ]]; then
  echo "Error: STORAGE_ACCOUNT_NAME must be 3-24 lowercase letters and numbers"
  echo "  Current: '$STORAGE_ACCOUNT_NAME'"
  exit 1
else
  echo "STORAGE_ACCOUNT_NAME format OK"
fi

echo ""
echo "=============================================="
echo "  Configuration validation complete!"
echo "=============================================="
echo ""
echo "Summary:"
echo "  Resource Group:    $RESOURCE_GROUP"
echo "  Location:          $LOCATION"
echo "  Storage Account:   $STORAGE_ACCOUNT_NAME"
echo ""
echo "Ready to proceed with deployment."
echo ""
