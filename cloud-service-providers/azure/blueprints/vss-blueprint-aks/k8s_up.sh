#!/bin/bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
pushd "${SCRIPT_DIR}" > /dev/null || exit
trap 'popd > /dev/null' EXIT

source ./configuration.sh

./secrets.sh

# GPU Operator (driver pre-installed on AKS GPU nodes)
echo "Installing NVIDIA GPU Operator..."
helm repo add nvidia https://helm.ngc.nvidia.com/nvidia --force-update
helm repo update nvidia

if helm status gpu-operator -n gpu-operator &>/dev/null; then
  echo "GPU Operator already installed, skipping."
else
  helm install gpu-operator nvidia/gpu-operator \
    -n gpu-operator --create-namespace \
    --set driver.enabled=false \
    --set toolkit.enabled=true
fi

echo "Waiting for GPU to be allocatable..."
for i in $(seq 1 30); do
  GPU_COUNT=$(kubectl get nodes -o json 2>/dev/null \
    | python3 -c "
import sys, json
data = json.load(sys.stdin)
for node in data.get('items', []):
    gpus = node.get('status', {}).get('allocatable', {}).get('nvidia.com/gpu', '0')
    if int(gpus) > 0:
        print(gpus)
        sys.exit(0)
print('0')
" 2>/dev/null || echo "0")

  if [ "$GPU_COUNT" != "0" ]; then
    echo "GPU available: $GPU_COUNT"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "WARNING: No GPU detected after 5 minutes. Continuing anyway..."
  fi
  sleep 10
done

# Deploy VSS via Helm
echo "Installing VSS blueprint..."
helm upgrade --install vss-blueprint "$SCRIPT_DIR/nvidia-blueprint-vss-2.4.1.tgz" \
  -f "$SCRIPT_DIR/overrides-single-gpu.yaml" \
  --disable-openapi-validation

# Health check — wait for all pods to be ready
echo "Waiting for all pods to be ready (this can take 15-30 minutes on first run)..."

TIMEOUT=1800
ELAPSED=0
INTERVAL=30

while [ $ELAPSED -lt $TIMEOUT ]; do
  echo "  [$(date +%H:%M:%S)] Pod status:"
  kubectl get pods --no-headers 2>/dev/null | while read -r line; do
    echo "    $line"
  done || true
  echo ""

  PODS_TABLE="$(kubectl get pods --no-headers 2>/dev/null | sed '/^No resources found/d')"

  FAILED_PODS=$(
    printf "%s\n" "$PODS_TABLE" | awk '
      $3 ~ /^(Failed|Error|CrashLoopBackOff|ImagePullBackOff|ErrImagePull)$/ {c++}
      END{print c+0}'
  )

  PENDING_PODS=$(
    printf "%s\n" "$PODS_TABLE" | awk '
      $3=="Pending" || $3=="ContainerCreating" || $3=="Init:0/1" || $3=="Init:0/2" || $3=="Init:0/3" || $3=="Init:0/4" || $3=="Init:0/5" || $3=="PodInitializing" {c++}
      END{print c+0}'
  )

  NOT_READY=$(
    printf "%s\n" "$PODS_TABLE" | awk '
      $3=="Running" {
        n=split($2,a,"/");
        if (n!=2 || a[1]!=a[2]) c++
      }
      END{print c+0}'
  )

  if [ "$FAILED_PODS" -gt 0 ]; then
    echo "WARNING: $FAILED_PODS pods in error state."
  fi

  if [ "$PENDING_PODS" -eq 0 ] && [ "$NOT_READY" -eq 0 ] && [ "$FAILED_PODS" -eq 0 ]; then
    echo "=== All pods ready! ==="
    break
  fi

  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
  echo ""
  echo "ERROR: Timed out after ${TIMEOUT}s waiting for pods to become ready."
  echo "Check pod status: kubectl get pods"
  echo "Check logs:       kubectl logs <pod-name>"
  exit 1
fi

echo ""
echo "Deployment complete."
echo ""
echo "  Access VSS:"
echo "    kubectl port-forward svc/vss-service 8100:8000 &"
echo "    kubectl port-forward svc/vss-service 9100:9000 &"
echo ""
echo "    API: http://localhost:8100"
echo "    UI:  http://localhost:9100"
echo ""
echo "  Test:"
echo "    curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8100/health/ready"
echo "    ./summarize_url.sh \"https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4\""
echo ""
