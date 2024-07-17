#!/bin/bash
set -x

# Check all env variables
env

# Check if NGC_API_KEY environment variable is set
if env | grep -q "NGC_API_KEY"; then
  echo "NGC API KEY: $NGC_API_KEY"
else
  echo "NGC API KEY is not set."
fi

# Start NIM server
bash /opt/nim/start-server.sh
