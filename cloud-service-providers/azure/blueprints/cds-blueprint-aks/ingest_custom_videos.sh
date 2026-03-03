#!/usr/bin/env bash

## Cosmos Dataset Search (CDS) — Ingest a video into a CDS collection.
##
## For public URLs the video is passed directly to the CDS API (no local
## download or blob upload). Local files are uploaded to Azure Blob Storage
## first so the cluster can reach them.
##
## Usage:
##   ./ingest_custom_videos.sh <collection-id> https://example.com/v.mp4
##   ./ingest_custom_videos.sh <collection-id> /path/to/video.mp4
##
## Prerequisites:
##   - CDS deployed (./k8s_up.sh)
##   - .storage-config file exists (created by storage_up.sh) — only needed
##     when ingesting local files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

COLLECTION_ID="${1:-}"
VIDEO_INPUT="${2:-}"

# Detect API base URL from ingress
INGRESS_IP=$(kubectl get ingress simple-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [ -z "$INGRESS_IP" ]; then
  echo "ERROR: Could not get ingress IP. Is the cluster running?"
  exit 1
fi
API_BASE="http://${INGRESS_IP}"

if [ -z "$COLLECTION_ID" ]; then
  echo "Usage: $0 <collection-id> <video-url-or-path>"
  echo ""
  echo "List collections:"
  echo "  curl -s $API_BASE/api/v1/collections | python3 -m json.tool"
  exit 1
fi

if [ -z "$VIDEO_INPUT" ]; then
  echo "ERROR: No video specified."
  echo "Usage: $0 <collection-id> <video-url-or-path>"
  exit 1
fi

# --------------------------------------------------------------------------
# Resolve video to an ingestible URL
# --------------------------------------------------------------------------
TEMP_VIDEO=""
cleanup() { [ -n "$TEMP_VIDEO" ] && rm -f "$TEMP_VIDEO"; true; }
trap cleanup EXIT

if [[ "$VIDEO_INPUT" == http* ]]; then
  # Public URL — pass directly to the CDS API; no download or blob upload.
  FILENAME=$(basename "$VIDEO_INPUT" | sed 's/[?#].*//')
  VIDEO_URL="$VIDEO_INPUT"
  echo "Using public URL: $VIDEO_URL"
elif [ -f "$VIDEO_INPUT" ]; then
  # Local file — upload to Azure Blob Storage so the cluster can reach it.
  if [ ! -f "$SCRIPT_DIR/.storage-config" ]; then
    echo "ERROR: .storage-config not found. Run storage_up.sh first."
    exit 1
  fi
  source "$SCRIPT_DIR/.storage-config"

  VIDEO_FILE="$VIDEO_INPUT"
  FILENAME=$(basename "$VIDEO_FILE")
  VIDEO_SIZE=$(wc -c < "$VIDEO_FILE" | tr -d ' ')
  echo "Uploading local file: $FILENAME ($((VIDEO_SIZE / 1024)) KB)"

  az storage blob upload \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --account-key "$STORAGE_KEY" \
    --container-name cds-videos \
    --name "$FILENAME" \
    --file "$VIDEO_FILE" \
    --overwrite \
    -o none 2>&1

  UPLOAD_URL="${BLOB_BASE_URL}/cds-videos/${FILENAME}"
  if [ -n "${SAS_TOKEN:-}" ]; then
    VIDEO_URL="${UPLOAD_URL}?${SAS_TOKEN}"
  else
    VIDEO_URL="${UPLOAD_URL}"
  fi
  echo "  URL: ${UPLOAD_URL}"
else
  echo "ERROR: Video not found: $VIDEO_INPUT"
  exit 1
fi
echo ""

# --------------------------------------------------------------------------
# Ingest via CDS API
# --------------------------------------------------------------------------
echo "--- Ingesting into collection $COLLECTION_ID ---"

RESP=$(curl -s -X POST "$API_BASE/api/v1/collections/$COLLECTION_ID/documents" \
  -H "Content-Type: application/json" \
  -d "[{\"url\": \"$VIDEO_URL\", \"mime_type\": \"video/mp4\", \"metadata\": {\"filename\": \"$FILENAME\"}}]" \
  --max-time 600)

echo "  $RESP"
echo ""

# --------------------------------------------------------------------------
# Flush and wait for indexing
# --------------------------------------------------------------------------
echo "--- Waiting for indexing ---"
curl -s -X POST "$API_BASE/api/v1/admin/collections/$COLLECTION_ID/flush" > /dev/null 2>&1 || true

MAX_WAIT=300
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
  DOC_COUNT=$(curl -s "$API_BASE/api/v1/collections/$COLLECTION_ID" | \
    python3 -c "import json,sys; print(json.load(sys.stdin).get('total_documents_count', 0))" 2>/dev/null || echo "0")

  if [ "$DOC_COUNT" -ge 1 ] 2>/dev/null; then
    echo "  Done. Documents in collection: $DOC_COUNT"
    break
  fi

  echo "  Waiting... (${ELAPSED}s)"
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done

echo ""
echo "Search:"
echo "  ./search.sh $COLLECTION_ID \"your search query\""
echo ""
echo "UI: $API_BASE/cosmos-dataset-search"
exit 0
