#!/bin/bash

# Graceful teardown for VSS on AKS.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
pushd "${SCRIPT_DIR}" > /dev/null || exit
trap 'popd > /dev/null' EXIT

if [ "$1" != "-y" ]; then
  read -p "Delete all VSS cluster resources? Press enter to continue."
fi

echo "Gracefully shutting down VSS..."

echo "Uninstalling Helm release..."
helm uninstall vss-blueprint || true

echo "Force deleting remaining pods..."
kubectl delete pods --all --grace-period=0 --force || true

echo "Deleting PVCs..."
kubectl delete pvc --all --timeout=60s || true

echo "Deleting secrets..."
kubectl delete secret \
  ngc-docker-reg-secret \
  ngc-api-key-secret \
  hf-token-secret \
  graph-db-creds-secret \
  arango-db-creds-secret \
  minio-creds-secret \
  2>/dev/null || true

echo "Waiting for load balancer cleanup..."
sleep 15

echo ""
echo "Cluster resources have been cleaned up."
echo ""
echo "To delete the entire AKS cluster and resource group:"
echo "  az group delete -n <resource-group> --yes"
echo ""
echo "To just stop GPU billing (keep cluster):"
echo "  az aks nodepool scale -g <resource-group> --cluster-name <cluster> -n gpupool --node-count 0"
