#!/bin/sh
if ! which curl > /dev/null; then
  CURL_VERSION=8.10.1
  wget "https://github.com/stunnel/static-curl/releases/download/${CURL_VERSION}/curl-linux-x86_64-${CURL_VERSION}.tar.xz"
  tar xf "curl-linux-x86_64-${CURL_VERSION}.tar.xz"
  alias curl="$PWD/curl"
fi

if ! which jq > /dev/null; then
  JQ_VERSION=1.7
  wget -q https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64 -O "$TEMP_DIR/jq"
  chmod +x "$TEMP_DIR/jq"
  alias jq="$TEMP_DIR/jq"
fi

SERVICE_FQDN=nim-gke-gcs-signed-url-722708171432.us-central1.run.app
cat <<EOF > "$TEMP_DIR/id_request.json"
{
"audience": "https://${SERVICE_FQDN}",
"includeEmail": "true"
}
EOF


TOKEN="$(curl -s -X GET -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token" | jq -r ".access_token")"

echo "token is: $TOKEN"
echo ""

EMAIL="$(curl -s -X GET -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email")"

echo "email is $EMAIL"
echo ""

ID_TOKEN="$(curl -s -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "@$TEMP_DIR/id_request.json" \
    "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${EMAIL}:generateIdToken" | jq -r ".token")"

echo "id token is $ID_TOKEN"
echo ""


echo "listing service accounts"
curl -X GET -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/"

echo ""
echo ""

echo "listing the project service account"


curl -X GET -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/sa-nim-inframgr@isv-coe-skhas-nvidia.iam.gserviceaccount.com/"

echo ""
echo ""

echo "listing the default service account"
curl -X GET -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/"

echo ""
echo ""

echo "grabbing an id token with the project service account"
ID_TOKEN=$(curl -X GET -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/sa-nim-inframgr@isv-coe-skhas-nvidia.iam.gserviceaccount.com/identity?audience=http://www.example.com&format=full")
echo $ID_TOKEN
echo ""
echo ""

echo "grabbing an id token with the default service account"
ID_TOKEN=$(curl -X GET -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity?audience=http://www.example.com&format=full")
echo $ID_TOKEN
echo ""
echo ""