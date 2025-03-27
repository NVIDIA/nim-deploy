#!/bin/sh

# use --token-format=full for print-identity-token if using GCE VM.
cat <<EOF > req.cred.json
{
  "bucket": "${NIM_GCS_BUCKET}",
  "text": "${NGC_EULA_TEXT}",
  "textb64": "$(echo ${NGC_EULA_TEXT} | base64 -w0)",
  "jwt": "$(gcloud auth print-identity-token)"
}
EOF

HTTP_URL="$(curl -s -X POST -H 'accept: application/json' -H 'Content-Type: application/json' -d @req.cred.json "https://${SERVICE_FQDN}/v1/request/${GCS_FILENAME}" | sed 's/.*\(https.*\)\\\\n.*/\1/g')"
echo -n "$HTTP_URL"
