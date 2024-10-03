#!/bin/sh

TEMP_DIR="$(mktemp -d)"

>&2 echo "=== DEBUG: Generated temp dir: $TEMP_DIR ==="

if ! which curl > /dev/null; then
  CURL_VERSION=8.10.1
  wget "https://github.com/stunnel/static-curl/releases/download/${CURL_VERSION}/curl-linux-x86_64-${CURL_VERSION}.tar.xz" -P "$TEMP_DIR"
  tar xf "$TEMP_DIR/curl-linux-x86_64-${CURL_VERSION}.tar.xz" -C "$TEMP_DIR"
  alias curl="$TEMP_DIR/curl"
fi

>&2 echo "=== DEBUG: Downloaded Curl: $(which curl) ==="

if ! which jq > /dev/null; then
  JQ_VERSION=1.7
  wget https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64 -O "$TEMP_DIR/jq"
  chmod +x "$TEMP_DIR/jq"
  alias jq="$TEMP_DIR/jq"
fi

>&2 echo "=== DEBUG: Downloaded JQ: $(which jq) ==="

if ! which gcloud > /dev/null; then
  cat <<EOF > "$TEMP_DIR/id_request.json"
{
"audience": "https://${SERVICE_FQDN}",
"includeEmail": "true"
}
EOF

  >&2 echo "=== DEBUG: Generated ID request ==="
  >&2 echo "=== DEBUG: id_request.json: $(cat $TEMP_DIR/id_request.json) ==="

  TOKEN="$(curl -v -X GET -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | jq -r ".access_token")"

  >&2 echo "=== DEBUG: Fetched access token: $TOKEN ==="

  EMAIL="$(curl -v -X GET -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email")"

  >&2 echo "=== DEBUG: Fetched email: $EMAIL ==="

  ID_TOKEN="$(curl -v -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "@$TEMP_DIR/id_request.json" \
    "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${EMAIL}:generateIdToken" | jq -r ".token")"

  >&2 echo "=== DEBUG: Fetched ID Token: $ID_TOKEN ==="

else
  ID_TOKEN="$(gcloud auth print-identity-token)"
fi

>&2 echo "=== DEBUG: Generated ID Token: $ID_TOKEN ==="

cat <<EOF > "$TEMP_DIR/req.cred.json"
{
  "bucket": "${NIM_GCS_BUCKET}",
  "text": "${NGC_EULA_TEXT}",
  "textb64": "$(echo ${NGC_EULA_TEXT} | base64 -w0)",
  "jwt": "$ID_TOKEN"
}
EOF

>&2 echo "=== DEBUG: Generated Signed URL request ==="
>&2 echo "=== DEBUG: req.cred.json: $(cat $TEMP_DIR/req.cred.json) ==="

HTTP_URL="$(curl -v -X POST -H 'accept: application/json' -H 'Content-Type: application/json' -d "@$TEMP_DIR/req.cred.json" "https://${SERVICE_FQDN}/v1/request/${GCS_FILENAME}" | sed 's/.*\(https.*\)\\\\n.*/\1/g')"

>&2 echo "=== DEBUG: Fetched HTTP_URL: $HTTP_URL ==="

echo -n "$HTTP_URL"