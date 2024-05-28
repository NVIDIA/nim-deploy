SCRIPT_DIR="$(dirname "$(realpath "$0")")"

source ${SCRIPT_DIR}/secrets.env

# Check if NGC_API_KEY is empty
if [ -z "$NGC_API_KEY" ]; then
  echo "Error: NGC_API_KEY is not set or is empty."
  exit 1
fi

# Check if HF_TOKEN is empty
if [ -z "$HF_TOKEN" ]; then
  echo "Error: HF_TOKEN is not set or is empty."
  exit 1
fi

# Check if NGC_TOKEN is empty
if [ -z "$NGC_API_KEY" ]; then
  echo "Error: NGC_TOKEN is not set or is empty."
  exit 1
fi

kubectl create secret docker-registry ngc-secret \
 --docker-server=nvcr.io\
 --docker-username='$oauthtoken'\
 --docker-password=${NGC_API_KEY}

# Encode the tokens to base64
HF_TOKEN_BASE64=$(echo -n "$HF_TOKEN" | base64 -w0)
NGC_API_KEY_BASE64=$(echo -n "$NGC_API_KEY" | base64 -w0)

# Replace placeholders in YAML and apply
sed -e "s|\${HF_TOKEN}|${HF_TOKEN_BASE64}|g" -e "s|\${NGC_API_KEY}|${NGC_API_KEY_BASE64}|g" ${SCRIPT_DIR}/nvidia-nim-secrets.yaml | kubectl apply -f -