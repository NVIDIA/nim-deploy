#!/bin/bash

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
KSERVE_DIR="${SCRIPT_DIR}/.."

# Setup location of NIM Cache on local system
sudo mkdir -p /raid/nvidia-nim/cache

bash ${SCRIPT_DIR}/create-secrets.sh

# NIMs require enabling NodeSelectors to specify GPU types
kubectl patch configmap config-features -n knative-serving --type merge -p '{"data":{"kubernetes.podspec-nodeselector":"enabled"}}'

# NIMs require enabling EmptyDir for use with shared memory
kubectl patch configmap config-features -n knative-serving --type merge -p '{"data":{"kubernetes.podspec-volumes-emptydir":"enabled"}}'

for runtime in `ls -d ${KSERVE_DIR}/runtimes/*yaml`; do
  kubectl create -f $runtime
done

NODE_NAME=${NODE_NAME:-"$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' | head -n1)"}
sed -i "/# XXX: Update this to match your hostname/c\               - ${NODE_NAME} # XXX: Update this to match your hostname/" scripts/nvidia-nim-cache.yaml
kubectl create -f ${SCRIPT_DIR}/nvidia-nim-cache.yaml
