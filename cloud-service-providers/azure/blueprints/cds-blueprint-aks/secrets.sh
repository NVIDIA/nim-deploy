#!/bin/bash

# Ensure NGC_API_KEY is set
if [ -z "$NGC_API_KEY" ]; then
  echo "Error: NGC_API_KEY is not set"
  exit 1
fi

# Create image pull secret for nvcr.io
echo "Creating nvcr.io image pull secret..."
kubectl create secret docker-registry ngc-docker-reg-secret \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password="$NGC_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl patch serviceaccount default -p '{"imagePullSecrets": [{"name": "ngc-docker-reg-secret"}]}'

# Create NGC API key secret (for NIM runtime access)
echo "Creating NGC API key secret..."
kubectl create secret generic ngc-api-key-secret \
  --from-literal=NGC_API_KEY="$NGC_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# Create ngc-secret (additional image pull secret matching cosmos-embed expectations)
kubectl create secret docker-registry ngc-secret \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password="$NGC_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "NGC secrets created successfully"

# Encryption key for CDS secrets management
if kubectl get secret secret-encryption-key > /dev/null 2>&1; then
    echo "Secret already exists, keeping existing SECRETS_ENCRYPTION_KEY"
else
    if [ -z "$SECRETS_ENCRYPTION_KEY" ]; then
        echo "Generating new SECRETS_ENCRYPTION_KEY..."
        export SECRETS_ENCRYPTION_KEY=$(openssl rand -base64 32)
    fi
    echo "Creating new secret with SECRETS_ENCRYPTION_KEY"
    kubectl create secret generic secret-encryption-key \
            --from-literal=SECRETS_ENCRYPTION_KEY="$SECRETS_ENCRYPTION_KEY"
fi
