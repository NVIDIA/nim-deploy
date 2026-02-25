#!/usr/bin/env bash
# Summarize a video from a URL using AKS-deployed VSS.
# Manages kubectl port-forward automatically.
# Output saved to ./summaries/<video>_<timestamp>/{summary.txt, response.json, run.log}
#
# Usage:
#   ./summarize_url.sh <VIDEO_URL>
#
# Examples:
#   ./summarize_url.sh "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4"

set -euo pipefail

VIDEO_URL="${1:?Usage: $0 <VIDEO_URL>}"
LOCAL_PORT="${2:-8100}"
VSS_HOST="http://localhost:${LOCAL_PORT}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

FILENAME="$(basename "${VIDEO_URL%%\?*}")"
[ -z "$FILENAME" ] && FILENAME="video.mp4"
BASENAME="${FILENAME%.*}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

RUN_DIR="${SCRIPT_DIR}/summaries/${BASENAME}_${TIMESTAMP}"
mkdir -p "$RUN_DIR"

LOG_FILE="${RUN_DIR}/run.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Ensure port-forward is running
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

TMPFILE=$(mktemp /tmp/vss_XXXXXX.mp4)
cleanup() {
  rm -f "$TMPFILE"
  if [ -n "$PF_PID" ]; then
    kill "$PF_PID" 2>/dev/null || true
    wait "$PF_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo ""
echo "  Video: $VIDEO_URL"
echo "  VSS:   $VSS_HOST (AKS)"

echo ""
echo "  DOWNLOAD"
curl -L --progress-bar "$VIDEO_URL" -o "$TMPFILE"
SIZE_MB=$(( $(stat -f%z "$TMPFILE" 2>/dev/null || stat -c%s "$TMPFILE" 2>/dev/null) / 1048576 ))
echo "  Saved: ${SIZE_MB} MB → $TMPFILE"

echo ""
echo "  UPLOAD → $VSS_HOST"
UPLOAD_RESPONSE=$(curl --progress-bar -X POST "${VSS_HOST}/files" \
  -F "file=@${TMPFILE};filename=${FILENAME}" \
  -F "purpose=vision" \
  -F "media_type=video")

rm -f "$TMPFILE"

FILE_ID=$(echo "$UPLOAD_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])" 2>/dev/null)
if [ -z "$FILE_ID" ]; then
  echo "  ERROR: Upload failed"
  echo "  $UPLOAD_RESPONSE"
  exit 1
fi
echo "  File ID: ${FILE_ID}"

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
export TXT_FILE VIDEO_URL WALL_TIME
echo "$SUMMARY_RESPONSE" | python3 -c "
import sys, json, os

r = json.load(sys.stdin)
txt_file = os.environ.get('TXT_FILE', '')
video_url = os.environ.get('VIDEO_URL', '')
wall_time = os.environ.get('WALL_TIME', '?')

lines = []
if 'choices' in r:
    summary = r['choices'][0]['message']['content']
    m = r.get('media_info', {})
    u = r.get('usage', {})

    lines.append(f'Video: {video_url}')
    lines.append(f'Duration: {m.get(\"end_offset\", \"?\")}s')
    lines.append(f'Chunks: {u.get(\"total_chunks_processed\", \"?\")}')
    lines.append(f'Processing time: {u.get(\"query_processing_time\", \"?\")}s')
    lines.append(f'Wall clock: {wall_time}s')
    lines.append('')
    lines.append(summary)

    print(summary)
    print()
    print(f'  Video duration:   {m.get(\"end_offset\", \"?\")}s')
    print(f'  Chunks processed: {u.get(\"total_chunks_processed\", \"?\")}')
    print(f'  Processing time:  {u.get(\"query_processing_time\", \"?\")}s')
else:
    err = json.dumps(r, indent=2)
    lines.append(f'ERROR: {err}')
    print('  ERROR:', err)

if txt_file:
    with open(txt_file, 'w') as f:
        f.write('\n'.join(lines) + '\n')
" 2>/dev/null

echo "  Wall clock:       ${WALL_TIME}s"
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
