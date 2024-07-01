#!/bin/sh

# Function to print usage
usage() {
  echo "Usage: $0 [-p PORT] [-b BACKEND_PORT] [-c CONFIG_URL] [-e ORIGINAL_ENTRYPOINT] [-a ORIGINAL_CMD]"
  echo "  -p PORT                Port to listen on (default: 8080)"
  echo "  -b BACKEND_PORT        Backend port (default: 80)"
  echo "  -c CONFIG_URL          URL or path of the configuration file (default: /opt/cadd-config.json)"
  echo "  -e ORIGINAL_ENTRYPOINT Path to the original entrypoint script (default: /usr/bin/serve)"
  echo "  -a ORIGINAL_CMD        Original command arguments (default: empty)"
  exit 1
}

# Default values
PORT=8080
BACKEND_PORT=8000
CONFIG_URL="/opt/caddy-config.json"
ORIGINAL_ENTRYPOINT="/usr/bin/serve"
ORIGINAL_CMD=""

# Parse command-line arguments
while getopts "p:b:c:e:a:" opt; do
  case ${opt} in
    p )
      PORT=${OPTARG}
      ;;
    b )
      BACKEND_PORT=${OPTARG}
      ;;
    c )
      CONFIG_URL=${OPTARG}
      ;;
    e )
      ORIGINAL_ENTRYPOINT=${OPTARG}
      ;;
    a )
      ORIGINAL_CMD=${OPTARG}
      ;;
    * )
      usage
      ;;
  esac
done

# Function to download a file
download_file() {
  url=$1
  output=$2
  curl -L -o "$output" "$url"
  if [ $? -ne 0 ]; then
    echo "Failed to download $url"
    exit 1
  fi
}

# Check if Caddy is already present
if [ ! -f "/usr/local/bin/caddy" ]; then
  echo "Caddy not found, downloading Caddy..."
  download_file "https://caddyserver.com/api/download?os=linux&arch=amd64" "/tmp/caddy"

  # Ensure the file is moved to its final destination
  mv /tmp/caddy /usr/local/bin/caddy

  # Make Caddy executable
  chmod +x /usr/local/bin/caddy
else
  echo "Caddy already present."
fi

# Check if CONFIG_URL is a URL or a local file path
if echo "$CONFIG_URL" | grep -qE '^https?://'; then
  # It's a URL, download the configuration file
  echo "Downloading configuration file from URL..."
  download_file "$CONFIG_URL" "/usr/local/bin/caddy-config.json"
  CONFIG_FILE_PATH="/usr/local/bin/caddy-config.json"
else
  # It's a local file path, use it directly
  echo "Using local configuration file..."
  CONFIG_FILE_PATH="$CONFIG_URL"
fi

# Create a temporary configuration file with substituted variables
CONFIG_FILE=$(mktemp)
cat "$CONFIG_FILE_PATH" | sed "s/\${PORT}/$PORT/g; s/\${BACKEND_PORT}/$BACKEND_PORT/g" > $CONFIG_FILE

# Ensure the configuration file is written correctly
if [ ! -s "$CONFIG_FILE" ]; then
  echo "Configuration file is empty or not created properly"
  exit 1
fi

# Debug: Display the configuration file content
cat $CONFIG_FILE

# Run Caddy with the temporary configuration file
echo "Running Caddy..."
/usr/local/bin/caddy run --config $CONFIG_FILE &

# Wait for a few seconds to ensure Caddy starts
sleep 5

env

# Execute the original container entrypoint script and command
if [ -f "$ORIGINAL_ENTRYPOINT" ]; then
    echo "Running original entrypoint script and command..."
    $ORIGINAL_ENTRYPOINT $ORIGINAL_CMD &
else
    echo "Original entrypoint script not found: $ORIGINAL_ENTRYPOINT"
    exit 1
fi

wait
