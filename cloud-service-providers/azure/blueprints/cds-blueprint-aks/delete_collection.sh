#!/usr/bin/env bash
# Delete a CDS collection.
#
# Usage:
#   ./delete_collection.sh <collection-id>

set -euo pipefail

COLLECTION_ID="${1:-}"

INGRESS_IP=$(kubectl get ingress simple-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [ -z "$INGRESS_IP" ]; then
  echo "ERROR: Could not get ingress IP. Is the cluster running?"
  exit 1
fi
API_BASE="http://${INGRESS_IP}"

if [ -z "$COLLECTION_ID" ]; then
  echo "Usage: $0 <collection-id>"
  echo ""
  echo "List collections:"
  echo "  curl -s $API_BASE/api/v1/collections | python3 -m json.tool"
  exit 1
fi

echo "Deleting collection: $COLLECTION_ID"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$API_BASE/api/v1/collections/$COLLECTION_ID")

if [ "$RESP" = "200" ] || [ "$RESP" = "204" ]; then
  echo "  Deleted."
else
  echo "ERROR: Delete returned HTTP $RESP"
  curl -s -X DELETE "$API_BASE/api/v1/collections/$COLLECTION_ID"
  exit 1
fi
