#!/bin/bash

# Graceful teardown for VSS on AKS.
# Only removes the VSS Helm release. Shared resources (secrets, PVCs)
# are left intact to avoid breaking other workloads on the same cluster.

set -euo pipefail

if [ "$1" != "-y" ]; then
  read -p "Uninstall the vss-blueprint Helm release? Press enter to continue."
fi

echo "Uninstalling vss-blueprint Helm release..."
helm uninstall vss-blueprint || true

echo "Waiting for pods to terminate..."
kubectl wait --for=delete pod -l app.kubernetes.io/instance=vss-blueprint --timeout=120s 2>/dev/null || true

echo ""
echo "VSS Helm release removed."
echo ""
echo "The following resources were NOT deleted (may be shared with other workloads):"
echo ""
echo "  Secrets:  ngc-docker-reg-secret, ngc-api-key-secret, hf-token-secret,"
echo "            graph-db-creds-secret, arango-db-creds-secret, minio-creds-secret"
echo "  PVCs:     Model cache volumes (retain data for faster re-deploy)"
echo ""
echo "To delete them manually:"
echo "  kubectl delete secret ngc-docker-reg-secret ngc-api-key-secret hf-token-secret \\"
echo "    graph-db-creds-secret arango-db-creds-secret minio-creds-secret"
echo "  kubectl delete pvc -l app.kubernetes.io/instance=vss-blueprint"
echo ""
echo "To stop GPU billing (keep cluster for re-deploy):"
echo "  az aks nodepool scale -g <resource-group> --cluster-name <cluster> -n gpupool --node-count 0"
echo ""
echo "To delete everything:"
echo "  az group delete -n <resource-group> --yes"
