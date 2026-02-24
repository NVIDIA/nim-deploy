#!/usr/bin/env bash

## Cosmos Dataset Search (CDS) — Ingest a video into a CDS collection.
##
## Uploads the video to Azure Blob Storage, then ingests via URL.
## The video is publicly accessible for UI playback — no port-forward needed.
##
## Usage:
##   ./ingest_custom_videos.sh <collection-id> /path/to/video.mp4
##   ./ingest_custom_videos.sh <collection-id> https://example.com/v.mp4
##
## Prerequisites:
##   - CDS deployed (./k8s_up.sh)
##   - .storage-config file exists (created by storage_up.sh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

COLLECTION_ID="${1:-}"
VIDEO_INPUT="${2:-}"

# Load storage config from storage_up.sh
if [ ! -f "$SCRIPT_DIR/.storage-config" ]; then
  echo "ERROR: .storage-config not found. Run storage_up.sh first."
  exit 1
fi
source "$SCRIPT_DIR/.storage-config"

# Detect API base URL from ingress
INGRESS_IP=$(kubectl get ingress simple-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [ -z "$INGRESS_IP" ]; then
  echo "ERROR: Could not get ingress IP. Is the cluster running?"
  exit 1
fi
API_BASE="http://${INGRESS_IP}"

if [ -z "$COLLECTION_ID" ]; then
  echo "Usage: $0 <collection-id> [video-url-or-path]"
  echo ""
  echo "List collections:"
  echo "  curl -s $API_BASE/api/v1/collections | python3 -m json.tool"
  exit 1
fi

# --------------------------------------------------------------------------
# Resolve video to a local file
# --------------------------------------------------------------------------
TEMP_VIDEO=""
cleanup() {
  if [ -n "$TEMP_VIDEO" ]; then
    rm -f "$TEMP_VIDEO"
  fi
}
trap cleanup EXIT

if [ -z "$VIDEO_INPUT" ]; then
  echo "ERROR: No video specified."
  echo "Usage: $0 <collection-id> <video-url-or-path>"
  exit 1
elif [[ "$VIDEO_INPUT" == http* ]]; then
  URL_FILENAME=$(basename "$VIDEO_INPUT" | sed 's/[?#].*//')
  echo "Downloading: $VIDEO_INPUT"
  TEMP_VIDEO="/tmp/${URL_FILENAME}"
  curl -sL "$VIDEO_INPUT" -o "$TEMP_VIDEO"
  VIDEO_FILE="$TEMP_VIDEO"
  echo "  Downloaded: $(du -h "$VIDEO_FILE" | cut -f1)"
elif [ -f "$VIDEO_INPUT" ]; then
  VIDEO_FILE="$VIDEO_INPUT"
  echo "Using local file: $VIDEO_FILE"
else
  echo "ERROR: Video not found: $VIDEO_INPUT"
  exit 1
fi

FILENAME=$(basename "$VIDEO_FILE")
VIDEO_SIZE=$(wc -c < "$VIDEO_FILE" | tr -d ' ')
echo "  File: $FILENAME ($((VIDEO_SIZE / 1024)) KB)"
echo ""

# --------------------------------------------------------------------------
# 1. Upload to Azure Blob Storage
# --------------------------------------------------------------------------
echo "--- Uploading to Azure Blob Storage ---"

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
echo ""

# --------------------------------------------------------------------------
# 2. Ingest via CDS API (pure curl — no python3 dependency)
# --------------------------------------------------------------------------
echo "--- Ingesting into collection $COLLECTION_ID ---"

RESP=$(curl -s -X POST "$API_BASE/api/v1/collections/$COLLECTION_ID/documents" \
  -H "Content-Type: application/json" \
  -d "[{\"url\": \"$VIDEO_URL\", \"mime_type\": \"video/mp4\", \"metadata\": {\"filename\": \"$FILENAME\"}}]" \
  --max-time 600)

echo "  $RESP"
echo ""

# --------------------------------------------------------------------------
# 3. Flush and wait for indexing
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
echo "UI: $API_BASE"
exit 0
