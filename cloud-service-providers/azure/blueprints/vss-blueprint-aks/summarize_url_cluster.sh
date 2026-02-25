#!/usr/bin/env bash
# Summarize a video by downloading and uploading entirely on-cluster.
# Video bytes never leave the AKS network — only the small JSON summarize
# request and response travel through the local port-forward.
#
# Output saved to ./summaries-cluster/<video>_<timestamp>/{summary.txt, response.json, run.log}
#
# Usage:
#   ./summarize_url_cluster.sh <VIDEO_URL>
#
# Examples:
#   ./summarize_url_cluster.sh "https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"

set -euo pipefail

VIDEO_URL="${1:?Usage: $0 <VIDEO_URL>}"
LOCAL_PORT="${2:-8100}"
VSS_HOST="http://localhost:${LOCAL_PORT}"
VSS_INTERNAL="http://vss-service:8000"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

FILENAME="$(basename "${VIDEO_URL%%\?*}")"
[ -z "$FILENAME" ] && FILENAME="video.mp4"
BASENAME="${FILENAME%.*}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

RUN_DIR="${SCRIPT_DIR}/summaries-cluster/${BASENAME}_${TIMESTAMP}"
mkdir -p "$RUN_DIR"

LOG_FILE="${RUN_DIR}/run.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Find a VSS pod to exec into
VSS_POD=$(kubectl get pods -l app=vss -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -z "$VSS_POD" ]; then
  VSS_POD=$(kubectl get pods --no-headers | awk '/^vss-vss-deployment/ && /Running/ {print $1; exit}')
fi
if [ -z "$VSS_POD" ]; then
  echo "  ERROR: No running VSS pod found"
  exit 1
fi
echo "  Exec pod: $VSS_POD"

# Ensure local port-forward for /summarize calls
PF_PID=""
if curl -s --max-time 2 "${VSS_HOST}/health/ready" >/dev/null 2>&1; then
  echo "  Port-forward already active on :${LOCAL_PORT}"
else
  echo "  Starting kubectl port-forward (svc/vss-service ${LOCAL_PORT}:8000)..."
  kubectl port-forward svc/vss-service "${LOCAL_PORT}:8000" >/dev/null 2>&1 &
  PF_PID=$!

  for i in $(seq 1 15); do
    if curl -s --max-time 2 "${VSS_HOST}/health/ready" >/dev/null 2>&1; then
      echo "  Port-forward ready."
      break
    fi
    if [ "$i" -eq 15 ]; then
      echo "  ERROR: Port-forward failed to become ready after 15s"
      kill "$PF_PID" 2>/dev/null || true
      exit 1
    fi
    sleep 1
  done
fi

cleanup() {
  if [ -n "$PF_PID" ]; then
    kill "$PF_PID" 2>/dev/null || true
    wait "$PF_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo ""
echo "  Video: $VIDEO_URL"
echo "  VSS:   $VSS_INTERNAL (in-cluster)"

echo ""
echo "  DOWNLOAD + UPLOAD (on-cluster)"
UPLOAD_START=$(date +%s)

UPLOAD_RESPONSE=$(kubectl exec "$VSS_POD" -c vss -- \
  env "VIDEO_URL=$VIDEO_URL" "FILENAME=$FILENAME" "VSS_INTERNAL=$VSS_INTERNAL" \
  bash -c '
  TMPFILE=$(mktemp /tmp/vss_cluster_XXXXXX)
  trap "rm -f $TMPFILE" EXIT

  echo "  Downloading..." >&2
  curl -sL "$VIDEO_URL" -o $TMPFILE
  SIZE=$(stat -c%s $TMPFILE 2>/dev/null || stat -f%z $TMPFILE 2>/dev/null)
  echo "  Downloaded: $(( SIZE / 1048576 )) MB" >&2

  echo "  Uploading to VSS..." >&2
  curl -s -X POST "$VSS_INTERNAL/files" \
    -F "file=@$TMPFILE;filename=$FILENAME" \
    -F "purpose=vision" \
    -F "media_type=video"
')

UPLOAD_END=$(date +%s)
UPLOAD_TIME=$(( UPLOAD_END - UPLOAD_START ))

FILE_ID=$(echo "$UPLOAD_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
if [ -z "$FILE_ID" ]; then
  echo "  ERROR: Upload failed"
  echo "  $UPLOAD_RESPONSE"
  exit 1
fi
echo "  File ID: ${FILE_ID}  (download+upload: ${UPLOAD_TIME}s)"

echo ""
echo "  SUMMARIZE (waiting for Cosmos-Reason2-8B)..."

START_TIME=$(date +%s)

SUMMARY_RESPONSE=$(curl -s -X POST "${VSS_HOST}/summarize" \
  -H "Content-Type: application/json" \
  -d "{
    \"id\": \"${FILE_ID}\",
    \"model\": \"Cosmos-Reason2-8B\",
    \"prompt\": \"Write a concise and clear dense caption for this video. Describe what you see happening, including any notable events, objects, people, and activities.\",
    \"caption_summarization_prompt\": \"Summarize the following video events in the format start_time:end_time:caption. The output should be bullet points.\",
    \"summary_aggregation_prompt\": \"Aggregate the captions into a clear, concise summary. Merge adjacent events with the same description. Output bullet points organized by topic.\",
    \"chunk_duration\": 30,
    \"enable_chat\": false
  }")

END_TIME=$(date +%s)
WALL_TIME=$(( END_TIME - START_TIME ))

JSON_FILE="${RUN_DIR}/response.json"
echo "$SUMMARY_RESPONSE" > "$JSON_FILE"

TXT_FILE="${RUN_DIR}/summary.txt"
echo ""
export TXT_FILE VIDEO_URL WALL_TIME UPLOAD_TIME
echo "$SUMMARY_RESPONSE" | python3 -c "
import sys, json, os

r = json.load(sys.stdin)
txt_file = os.environ.get('TXT_FILE', '')
video_url = os.environ.get('VIDEO_URL', '')
wall_time = os.environ.get('WALL_TIME', '?')
upload_time = os.environ.get('UPLOAD_TIME', '?')

lines = []
if 'choices' in r:
    summary = r['choices'][0]['message']['content']
    m = r.get('media_info', {})
    u = r.get('usage', {})

    lines.append(f'Video: {video_url}')
    lines.append(f'Duration: {m.get(\"end_offset\", \"?\")}s')
    lines.append(f'Chunks: {u.get(\"total_chunks_processed\", \"?\")}')
    lines.append(f'Download+Upload (cluster): {upload_time}s')
    lines.append(f'Processing time: {u.get(\"query_processing_time\", \"?\")}s')
    lines.append(f'Wall clock: {wall_time}s')
    lines.append('')
    lines.append(summary)

    print(summary)
    print()
    print(f'  Video duration:           {m.get(\"end_offset\", \"?\")}s')
    print(f'  Chunks processed:         {u.get(\"total_chunks_processed\", \"?\")}')
    print(f'  Download+Upload (cluster): {upload_time}s')
    print(f'  Processing time:          {u.get(\"query_processing_time\", \"?\")}s')
else:
    err = json.dumps(r, indent=2)
    lines.append(f'ERROR: {err}')
    print('  ERROR:', err)

if txt_file:
    with open(txt_file, 'w') as f:
        f.write('\n'.join(lines) + '\n')
" 2>/dev/null

echo "  Wall clock:               ${WALL_TIME}s"
echo ""
echo "  Saved: $RUN_DIR/"
echo "         summary.txt | response.json | run.log"

echo ""
echo "  CLEANUP"
curl -s -X DELETE "${VSS_HOST}/files/${FILE_ID}" | python3 -c "
import sys, json
r = json.load(sys.stdin)
print(f'  Deleted: {r.get(\"deleted\", False)}')
" 2>/dev/null

echo ""
