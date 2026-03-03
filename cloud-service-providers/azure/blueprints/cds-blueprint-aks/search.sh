#!/usr/bin/env bash
# Search a CDS collection with a text query.
#
# Usage:
#   ./search.sh <collection-id> "person walking outdoors"
#   ./search.sh <collection-id> "car driving at night" 10

set -euo pipefail

COLLECTION_ID="${1:-}"
QUERY="${2:-}"
TOP_K="${3:-5}"

INGRESS_IP=$(kubectl get ingress simple-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [ -z "$INGRESS_IP" ]; then
  echo "ERROR: Could not get ingress IP. Is the cluster running?"
  exit 1
fi
API_BASE="http://${INGRESS_IP}"

if [ -z "$COLLECTION_ID" ] || [ -z "$QUERY" ]; then
  echo "Usage: $0 <collection-id> \"search query\" [top_k]"
  echo ""
  echo "List collections:"
  echo "  curl -s $API_BASE/api/v1/collections | python3 -m json.tool"
  exit 1
fi

RESP=$(curl -s -X POST "$API_BASE/api/v1/collections/$COLLECTION_ID/search" \
  -H "Content-Type: application/json" \
  -d "{
    \"query\": [{\"type\": \"text\", \"text\": \"$QUERY\"}],
    \"top_k\": $TOP_K
  }")

RESULT_COUNT=$(echo "$RESP" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('retrievals', [])))" 2>/dev/null || echo "?")
echo "Query: \"$QUERY\" (top $TOP_K)"
echo "Results: $RESULT_COUNT"
echo ""
echo "$RESP" | python3 -m json.tool 2>/dev/null || echo "$RESP"
