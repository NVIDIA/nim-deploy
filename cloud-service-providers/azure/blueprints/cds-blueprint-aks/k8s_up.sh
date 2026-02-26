#!/bin/bash

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
pushd "${SCRIPT_DIR}" > /dev/null || exit
trap 'popd > /dev/null' EXIT

source ./configuration.sh

./secrets.sh

# Load storage credentials (created by storage_up.sh)
if [ ! -f "$SCRIPT_DIR/.storage-config" ]; then
  echo "ERROR: .storage-config not found. Run storage_up.sh first."
  exit 1
fi
source "$SCRIPT_DIR/.storage-config"

kubectl apply -f visual-search/templates/secret-access-rbac.yaml

helm dependency build ./triton-cosmos-embed 2>/dev/null || true
helm upgrade --install cosmos-embed ./triton-cosmos-embed \
  --values cosmos-embed-override.yaml \
  --timeout 45m

helm upgrade --install visual-search visual-search \
  --values values.yaml \
  --set "env.NVIDIA_API_KEY=$NGC_API_KEY"

helm repo add milvus https://zilliztech.github.io/milvus-helm 2>/dev/null || true
helm repo update milvus

helm upgrade --install milvus milvus/milvus \
  --version 4.2.58 \
  -f milvus-values.yaml \
  --set "externalS3.accessKey=$STORAGE_ACCOUNT_NAME" \
  --set "externalS3.secretKey=$STORAGE_KEY"

# Wait for Milvus
echo "Waiting for Milvus..."
kubectl rollout status statefulset/milvus --timeout=600s 2>/dev/null \
  || kubectl rollout status deployment/milvus --timeout=600s 2>/dev/null \
  || echo "  (continuing — visual-search has its own init container wait)"

# TLS certificate (self-signed)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout privateKey.key -out certificate.crt \
  -subj "/C=US/ST=Texas/L=Austin/O=NVIDIA/OU=CDS/CN=self-signed-tls" 2>/dev/null
kubectl create secret tls visual-search-tls \
  --key privateKey.key --cert certificate.crt \
  --dry-run=client -o yaml | kubectl apply -f -
rm -f privateKey.key certificate.crt

# NGINX Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.6.4/deploy/static/provider/cloud/deploy.yaml 2>/dev/null
kubectl wait --namespace ingress-nginx \
  --for=condition=Available \
  --timeout=180s \
  deployment/ingress-nginx-controller 2>/dev/null || true

echo "Waiting for admission webhook to be fully operational..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s 2>/dev/null || true

echo "Giving webhook service 15 seconds to stabilize..."
sleep 15

# Delete our ingress before re-applying to avoid admission webhook path conflicts.
# Uses a label selector so we don't touch unrelated ingress resources.
kubectl delete ingress -l app.kubernetes.io/managed-by=cds-blueprint 2>/dev/null || true

echo "Creating ingress resource..."
MAX_RETRIES=3
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if kubectl apply -f ingress/ingress.yaml 2>&1 | tee /tmp/ingress_apply.log; then
    echo "Ingress created successfully"
    break
  else
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Ingress creation failed. Error details:"
    cat /tmp/ingress_apply.log
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      echo "Retrying in 15s... (attempt $RETRY_COUNT/$MAX_RETRIES)"
      sleep 15
    else
      echo "Failed to create ingress after $MAX_RETRIES attempts"
      kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50
      exit 1
    fi
  fi
done

# Wait for ingress to get an external IP
echo "Waiting for ingress IP..."
INGRESS_IP=""
for i in $(seq 1 30); do
  INGRESS_IP=$(kubectl get ingress simple-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  if [ -n "$INGRESS_IP" ]; then break; fi
  sleep 10
done

if [ -z "$INGRESS_IP" ]; then
  echo "WARNING: Could not get ingress IP. Check: kubectl get ingress simple-ingress"
  INGRESS_IP="<pending>"
fi
echo "Ingress IP: $INGRESS_IP"

# React UI — --force resolves field-manager conflicts from any prior kubectl set env
echo "Installing visual-search-react-ui with ingress IP: $INGRESS_IP"
helm upgrade --install visual-search-react-ui ./visual-search-react-ui \
  --values values.yaml \
  --values visual-search-react-ui/values.yaml \
  --set global.ingress.host="$INGRESS_IP" \
  --force-replace

# Final health check
echo "Performing final health check for all services..."

TIMEOUT=1800
ELAPSED=0
INTERVAL=30

while [ $ELAPSED -lt $TIMEOUT ]; do
  echo "  [$(date +%H:%M:%S)] Pod status:"
  kubectl get pods --no-headers 2>/dev/null | while read -r line; do
    echo "    $line"
  done
  echo ""

  PODS_TABLE="$(kubectl get pods --no-headers 2>/dev/null | sed '/^No resources found/d')"

  FAILED_PODS=$(
    printf "%s\n" "$PODS_TABLE" | awk '
      $3 ~ /^(Failed|Error|CrashLoopBackOff|ImagePullBackOff|ErrImagePull)$/ {c++}
      END{print c+0}'
  )

  PENDING_PODS=$(
    printf "%s\n" "$PODS_TABLE" | awk '
      $3=="Pending" || $3=="ContainerCreating" {c++}
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

echo ""
echo "Deployment completed successfully."
echo ""
echo "  UI:   http://${INGRESS_IP}/cosmos-dataset-search"
echo "  API:  http://${INGRESS_IP}/api/health"
echo "  Docs: http://${INGRESS_IP}/api/docs"
echo ""
echo "  Storage: ${BLOB_BASE_URL}/cds-videos/"
echo ""
echo "Next: create a collection and ingest videos"
echo "  ./create_collection.sh my-videos"
echo "  ./ingest_custom_videos.sh <collection-id> <video-url-or-path>"
