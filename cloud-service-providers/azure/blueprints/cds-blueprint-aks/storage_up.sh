#!/bin/bash

set -euo pipefail

# Azure Blob Storage setup for CDS (analogous to s3_up.sh in the EKS blueprint).
# Creates an Azure Storage Account with two containers:
#   cds-videos  — public video files (browser-accessible with SAS token)
#   cds-milvus  — Milvus vector data (private)
#
# Also creates the s3-access-sa Kubernetes service account.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
pushd "${SCRIPT_DIR}" > /dev/null || exit
trap 'popd > /dev/null' EXIT

# Reuse existing storage account if .storage-config exists from a prior run.
# This prevents creating a new account while Milvus etcd still points to the old one.
if [ -f "$SCRIPT_DIR/.storage-config" ]; then
  echo "Found existing .storage-config — reusing storage account."
  source "$SCRIPT_DIR/.storage-config"
  export STORAGE_ACCOUNT_NAME
fi

source ./configuration.sh

SERVICE_ACCOUNT_NAME="s3-access-sa"
NAMESPACE="default"

# --------------------------------------------------------------------------
# Create Azure Storage Account
# --------------------------------------------------------------------------
echo "Creating Azure Storage Account..."

if ! az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
  az storage account create \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --allow-blob-public-access true \
    -o none
  echo "Storage account created successfully."
else
  echo "Storage account '$STORAGE_ACCOUNT_NAME' already exists. Proceeding..."
fi

STORAGE_KEY=$(az storage account keys list \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query '[0].value' -o tsv)

# Create containers
az storage container create \
  --name cds-videos \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --account-key "$STORAGE_KEY" \
  -o none 2>/dev/null || true

az storage container create \
  --name cds-milvus \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --account-key "$STORAGE_KEY" \
  -o none 2>/dev/null || true

BLOB_BASE_URL="https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net"

# Configure CORS so the browser can fetch videos from Azure Blob
az storage cors add \
  --services b \
  --methods GET HEAD OPTIONS \
  --origins '*' \
  --allowed-headers '*' \
  --exposed-headers '*' \
  --max-age 3600 \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --account-key "$STORAGE_KEY" \
  -o none 2>/dev/null || true

# Generate a read-only SAS token for browser access to videos (valid 1 year)
EXPIRY=$(date -u -v+365d '+%Y-%m-%dT%H:%MZ' 2>/dev/null || date -u -d '+365 days' '+%Y-%m-%dT%H:%MZ')
SAS_TOKEN=$(az storage container generate-sas \
  --name cds-videos \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --account-key "$STORAGE_KEY" \
  --permissions r \
  --expiry "$EXPIRY" \
  -o tsv)

# Save storage config for other scripts
cat > "$SCRIPT_DIR/.storage-config" <<STORAGEEOF
STORAGE_ACCOUNT_NAME='$STORAGE_ACCOUNT_NAME'
STORAGE_KEY='$STORAGE_KEY'
BLOB_BASE_URL='$BLOB_BASE_URL'
SAS_TOKEN='$SAS_TOKEN'
STORAGEEOF
chmod 600 "$SCRIPT_DIR/.storage-config"

# --------------------------------------------------------------------------
# Create Kubernetes service account
# --------------------------------------------------------------------------
echo "Creating Kubernetes service account: $SERVICE_ACCOUNT_NAME"
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $SERVICE_ACCOUNT_NAME
  namespace: $NAMESPACE
EOF

echo ""
echo "Storage Account: $STORAGE_ACCOUNT_NAME"
echo "  Video URL:   ${BLOB_BASE_URL}/cds-videos/<filename>"
echo "  Milvus:      ${BLOB_BASE_URL}/cds-milvus/"
echo "Service account '$SERVICE_ACCOUNT_NAME' created in namespace '$NAMESPACE'."
