#!/bin/bash

set -eo pipefail

if [ -z "$NGC_API_KEY" ]; then
  echo "Error: NGC_API_KEY is not set"
  exit 1
fi

if [ -z "$HF_TOKEN" ]; then
  echo "Error: HF_TOKEN is not set"
  exit 1
fi

echo "Creating Kubernetes secrets..."

kubectl create secret docker-registry ngc-docker-reg-secret \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password="$NGC_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# WARNING: These credentials match the Helm chart's internal defaults.
# The chart's Neo4j, ArangoDB, and MinIO sub-charts expect these exact
# values. Changing them here requires matching overrides in the Helm
# values for every sub-chart that references these secrets.
# For production, override all sub-chart credential configurations.

kubectl create secret generic graph-db-creds-secret \
  --from-literal=username=neo4j --from-literal=password=password \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic arango-db-creds-secret \
  --from-literal=username=root --from-literal=password=password \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic minio-creds-secret \
  --from-literal=access-key=minio --from-literal=secret-key=minio123 \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic ngc-api-key-secret \
  --from-literal=NGC_API_KEY="$NGC_API_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic hf-token-secret \
  --from-literal=HF_TOKEN="$HF_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "All secrets created successfully."
