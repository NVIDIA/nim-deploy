#!/usr/bin/env bash
# Copy the newest Cursor parent-agent transcript JSONL into conversation-export.jsonl.
# Uses macOS/BSD find + ls; intended for local dev (path layout matches Cursor on disk).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSHOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT="$WORKSHOP_DIR/conversation-export.jsonl"

if [[ -n "${CONVERSATION_EXPORT_TRANSCRIPT:-}" ]]; then
  SRC="$CONVERSATION_EXPORT_TRANSCRIPT"
  if [[ ! -f "$SRC" ]]; then
    echo "CONVERSATION_EXPORT_TRANSCRIPT is not a file: $SRC" >&2
    exit 1
  fi
else
  ROOT="${CURSOR_AGENT_TRANSCRIPTS_ROOT:-$HOME/.cursor/projects}"
  if [[ ! -d "$ROOT" ]]; then
    echo "Transcript root missing: $ROOT (set CURSOR_AGENT_TRANSCRIPTS_ROOT if needed)" >&2
    exit 1
  fi
  # Matches .../agent-transcripts/<uuid>/<uuid>.jsonl
  SRC="$(find "$ROOT" -path '*/agent-transcripts/*/*.jsonl' -type f -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -n1 || true)"
  if [[ -z "$SRC" || ! -f "$SRC" ]]; then
    echo "No *.jsonl found under $ROOT/**/agent-transcripts/" >&2
    exit 1
  fi
fi

PH="${CONVERSATION_EXPORT_HOME_PLACEHOLDER:-__USER_HOME__}"

cp "$SRC" "$OUT"
# Redact local home prefix in the export only (paths appear in JSON/tool payloads).
export PH
perl -i -pe 'BEGIN { $p = $ENV{PH} // "__USER_HOME__" } s#/Users/anslutsky#$p#g; s#\\/Users\\/anslutsky#$p#g' "$OUT"

echo "Updated $OUT <= $SRC (redacted /Users/anslutsky -> ${PH})"
