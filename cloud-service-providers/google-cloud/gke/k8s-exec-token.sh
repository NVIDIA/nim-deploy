UTIL_DIR=/tmp/k8s-exec-token-plugin
mkdir -p "$UTIL_DIR"

if [ ! -f "$UTIL_DIR/curl" ]; then
  CURL_VERSION=8.10.1
  wget -q "https://github.com/stunnel/static-curl/releases/download/${CURL_VERSION}/curl-linux-x86_64-${CURL_VERSION}.tar.xz" -P "$UTIL_DIR"
  tar xf "$UTIL_DIR/curl-linux-x86_64-${CURL_VERSION}.tar.xz" -C "$UTIL_DIR"
fi

if [ ! -f "$UTIL_DIR/jq" ]; then
  JQ_VERSION=1.7
  wget -q "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64" -O "$UTIL_DIR/jq"
  chmod +x "$UTIL_DIR/jq"
fi

if ! which gke-gcloud-auth-plugin > /dev/null; then
  RESULT="$($UTIL_DIR/curl -s -X GET -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token")"
  ACCESS_TOKEN="$(echo $RESULT | $UTIL_DIR/jq -r ".access_token")"
  EXPIRES_IN="$(echo $RESULT | $UTIL_DIR/jq -r ".expires_in")"
  DATE_NOW="$(date +%s)"
  EXPIRES_AT="$(expr $DATE_NOW + $EXPIRES_IN)"
  EXPIRATION_TIMESTAMP="$(date -d@$EXPIRES_AT --utc +%Y-%m-%dT%H:%M:%SZ)"

  cat <<EOF
{
    "kind": "ExecCredential",
    "apiVersion": "client.authentication.k8s.io/v1beta1",
    "spec": {
        "interactive": false
    },
    "status": {
        "expirationTimestamp": "$EXPIRATION_TIMESTAMP",
        "token": "$ACCESS_TOKEN"
    }
}
EOF
else
  gke-gcloud-auth-plugin
fi
