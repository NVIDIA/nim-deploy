#!/bin/bash
set -e

# S3 to RAG Batch Ingestion Script
# Downloads files from S3 and uploads them to RAG ingestor using NVIDIA's batch_ingestion.py

# Configuration
S3_BUCKET_NAME="${S3_BUCKET_NAME:?Error: S3_BUCKET_NAME is required}"
INGESTOR_URL="${INGESTOR_URL:?Error: INGESTOR_URL is required}"
S3_PREFIX="${S3_PREFIX:-}"
RAG_COLLECTION_NAME="${RAG_COLLECTION_NAME:-multimodal_data}"
LOCAL_DATA_DIR="${LOCAL_DATA_DIR:-/tmp/s3_ingestion}"
UPLOAD_BATCH_SIZE="${UPLOAD_BATCH_SIZE:-100}"

# Parse INGESTOR_URL to extract host and port (expects format: host:port)
INGESTOR_HOST="${INGESTOR_URL%%:*}"
INGESTOR_PORT="${INGESTOR_URL##*:}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMP_DIR="${SCRIPT_DIR}/.tmp_ingestion"
VENV_DIR="${TEMP_DIR}/venv"

echo "📦 Setting up batch ingestion tools..."
mkdir -p "$TEMP_DIR"

# Download batch_ingestion.py from NVIDIA RAG repository
if [ ! -f "$TEMP_DIR/batch_ingestion.py" ]; then
  echo "📥 Downloading batch_ingestion.py from NVIDIA RAG repo..."
  curl -sL -o "$TEMP_DIR/batch_ingestion.py" \
    https://raw.githubusercontent.com/NVIDIA-AI-Blueprints/rag/v2.3.0/scripts/batch_ingestion.py
fi

# Download requirements.txt
if [ ! -f "$TEMP_DIR/requirements.txt" ]; then
  echo "📥 Downloading requirements.txt..."
  curl -sL -o "$TEMP_DIR/requirements.txt" \
    https://raw.githubusercontent.com/NVIDIA-AI-Blueprints/rag/v2.3.0/scripts/requirements.txt
fi

# Create virtual environment
echo "🐍 Creating Python virtual environment..."
python3 -m venv "$VENV_DIR"

# Activate virtual environment and install dependencies
echo "📦 Installing Python dependencies in virtual environment..."
source "$VENV_DIR/bin/activate"
pip install --quiet --upgrade pip
pip install --quiet -r "$TEMP_DIR/requirements.txt"

# Download files from S3
echo "📥 Downloading files from S3..."
mkdir -p "$LOCAL_DATA_DIR"
aws s3 sync "s3://$S3_BUCKET_NAME/$S3_PREFIX" "$LOCAL_DATA_DIR" \
  --exclude "*" --include "*.pdf" --include "*.docx" --include "*.txt"

# Count files
FILE_COUNT=$(find "$LOCAL_DATA_DIR" -type f | wc -l)
echo "✅ Downloaded $FILE_COUNT files from S3"

if [ "$FILE_COUNT" -eq 0 ]; then
  echo "❌ No files found to ingest"
  rm -rf "$LOCAL_DATA_DIR" "$TEMP_DIR"
  exit 1
fi

# Run batch ingestion using NVIDIA's script (in venv)
echo "📤 Starting batch upload to RAG ingestor..."
python3 "$TEMP_DIR/batch_ingestion.py" \
  --folder "$LOCAL_DATA_DIR" \
  --collection-name "$RAG_COLLECTION_NAME" \
  --create_collection \
  --ingestor-host "$INGESTOR_HOST" \
  --ingestor-port "$INGESTOR_PORT" \
  --upload-batch-size "$UPLOAD_BATCH_SIZE" \
  -v

# Deactivate virtual environment
deactivate

# Cleanup
echo "🧹 Cleaning up temporary files..."
rm -rf "$LOCAL_DATA_DIR"
rm -rf "$TEMP_DIR"

echo "✅ Batch ingestion complete!"

