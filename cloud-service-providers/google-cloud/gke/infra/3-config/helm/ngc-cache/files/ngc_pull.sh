#!/bin/bash

set -euo pipefail

export CACHE_PATH="$NIM_CACHE_PATH"

if [ -n "${NGC_BUNDLE_URL:-}" ]; then
  # Create a sub-directory, as tar tries to modify the parent folder permissions
  export CACHE_PATH="$NIM_CACHE_PATH/cache"
  mkdir "$CACHE_PATH"
  MODEL_BUNDLE_FILENAME="model.tar"
  # Fetch and extract from the provided URL, with max concurrency
  aria2c -x 16 -s 16 -j 10 --dir "$CACHE_PATH" --out="$MODEL_BUNDLE_FILENAME" "$NGC_BUNDLE_URL"
  tar xf "$CACHE_PATH/$MODEL_BUNDLE_FILENAME" -C "$CACHE_PATH"
  rm "$CACHE_PATH/$MODEL_BUNDLE_FILENAME"
else
  # Fetch directly from NGC to $NIM_CACHE_PATH
  download-to-cache
fi

find $CACHE_PATH -type d -printf '%P\n' | xargs -P 100 -I {} mkdir -p /upload-dir/{}
find $CACHE_PATH -type f,l -printf '%P\n' | xargs -P 100 -I {} cp --no-dereference $CACHE_PATH/{} /upload-dir/{}
