#!/bin/bash

# Graceful teardown for CDS on AKS.
# Mirrors the EKS teardown/shutdown_sequence.sh structure.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
pushd "${SCRIPT_DIR}" > /dev/null || exit
trap 'popd > /dev/null' EXIT

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-cds-aks}"

# Check required environment variables
if [ -z "$RESOURCE_GROUP" ]; then
  echo "Error: RESOURCE_GROUP is not set"
  exit 1
fi

# Skip confirmation with -y
if [ "$1" != "-y" ]; then
  read -p "Delete all cluster resources including storage account? Press enter to continue."
fi

###################### Graceful Application Shutdown ######################
echo "Gracefully shutting down applications..."

# Delete ingress first to prevent orphaned load balancers
kubectl delete ingress simple-ingress || true

# Delete Helm releases
echo "Uninstalling Helm releases..."
helm uninstall visual-search-react-ui || true
helm uninstall visual-search || true
helm uninstall cosmos-embed || true
helm uninstall milvus || true

# Force delete remaining pods
echo "Force deleting remaining pods..."
kubectl delete pods --all --grace-period=0 --force || true

# Delete PVCs
echo "Deleting PVCs..."
kubectl delete pvc --all --timeout=60s || true

# Clean up secrets and RBAC
echo "Deleting secrets and RBAC..."
kubectl delete secret ngc-docker-reg-secret ngc-api-key-secret ngc-secret secret-encryption-key visual-search-tls || true
kubectl delete sa s3-access-sa || true
kubectl delete role secret-access-role || true
kubectl delete rolebinding secret-access-binding || true

# Delete ingress-nginx namespace
echo "Deleting ingress-nginx namespace..."
kubectl delete ns ingress-nginx || true

# Wait for load balancers to clean up
echo "Waiting for load balancer cleanup..."
sleep 30

###################### Delete Azure Storage Account ######################
if [ -f "$SCRIPT_DIR/../.storage-config" ]; then
  source "$SCRIPT_DIR/../.storage-config"
  if [ -n "$STORAGE_ACCOUNT_NAME" ]; then
    echo "Deleting Azure Storage Account: $STORAGE_ACCOUNT_NAME"
    az storage account delete \
      --name "$STORAGE_ACCOUNT_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --yes || true
    echo "Storage account deleted."
  fi
else
  echo "No .storage-config found, skipping storage account deletion."
  echo "If needed, delete manually: az storage account delete --name <name> --resource-group $RESOURCE_GROUP --yes"
fi

###################### Delete AKS Cluster (optional) ######################
echo ""
echo "Cluster resources have been cleaned up."
echo ""
echo "To delete the entire AKS cluster and resource group:"
echo "  az group delete -n $RESOURCE_GROUP --yes"
echo ""
echo "To just stop GPU billing (keep cluster):"
echo "  az aks nodepool scale -g $RESOURCE_GROUP --cluster-name <cluster> -n gpupool --node-count 0"
