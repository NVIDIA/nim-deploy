#!/usr/bin/env bash
# Create a CDS collection.
#
# Usage:
#   ./create_collection.sh                     # creates "demo" collection
#   ./create_collection.sh my-dashcam-videos

set -euo pipefail

COLLECTION_NAME="${1:-demo}"
PIPELINE="cosmos_video_search_milvus"

INGRESS_IP=$(kubectl get ingress simple-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [ -z "$INGRESS_IP" ]; then
  echo "ERROR: Could not get ingress IP. Is the cluster running?"
  exit 1
fi
API_BASE="http://${INGRESS_IP}"

echo "Creating collection: $COLLECTION_NAME"
RESP=$(curl -s -X POST "$API_BASE/api/v1/collections" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"$COLLECTION_NAME\",
    \"description\": \"Created by create_collection.sh\",
    \"pipeline\": \"$PIPELINE\"
  }")

COLLECTION_ID=$(echo "$RESP" | python3 -c "import json,sys; print(json.load(sys.stdin)['collection']['id'])" 2>/dev/null || echo "")
if [ -z "$COLLECTION_ID" ]; then
  echo "ERROR: Failed to create collection"
  echo "  $RESP"
  exit 1
fi

echo "  ID: $COLLECTION_ID"
echo ""
echo "Next: ingest videos"
echo "  ./ingest_custom_videos.sh $COLLECTION_ID /path/to/video.mp4"
echo "  ./ingest_custom_videos.sh $COLLECTION_ID https://example.com/video.mp4"
