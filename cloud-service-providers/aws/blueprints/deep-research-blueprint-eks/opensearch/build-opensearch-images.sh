#!/bin/bash
# SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

# Simple script to build and push OpenSearch-enabled RAG Docker images to ECR

set -e

# Required environment variables
REGION=${REGION:-us-east-1}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE_TAG=${IMAGE_TAG:-2.3.0-opensearch}

# Image names
RAG_IMAGE="nvidia-rag-server"
INGESTOR_IMAGE="nvidia-rag-ingestor"

echo "🚀 Building OpenSearch-enabled RAG images..."
echo "Region: $REGION"
echo "Registry: $ECR_REGISTRY"
echo "Tag: $IMAGE_TAG"

# Create ECR repositories if they don't exist
echo "📦 Creating ECR repositories..."
aws ecr create-repository --repository-name $RAG_IMAGE --region $REGION 2>/dev/null || echo "Repository $RAG_IMAGE already exists"
aws ecr create-repository --repository-name $INGESTOR_IMAGE --region $REGION 2>/dev/null || echo "Repository $INGESTOR_IMAGE already exists"

# Login to ECR
echo "🔐 Logging into ECR..."
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ECR_REGISTRY

# Determine script directory and navigate to rag directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RAG_DIR="$SCRIPT_DIR/../rag"

# Check if rag directory exists
if [ ! -d "$RAG_DIR" ]; then
    echo "❌ Error: rag directory not found at $RAG_DIR"
    echo "Please ensure you have completed Step 12-OS (git clone and file integration)"
    echo "The rag repository should be cloned in the deep-research-blueprint-eks directory"
    exit 1
fi

# Build and push images
echo "🏗️ Building images..."
cd "$RAG_DIR"

# Update uv.lock file to match pyproject.toml with OpenSearch dependencies
echo "📝 Updating uv.lock file..."
if command -v uv &> /dev/null; then
    uv lock
else
    echo "⚠️  uv not found locally, attempting to build anyway..."
    echo "    If build fails, install uv: curl -LsSf https://astral.sh/uv/install.sh | sh"
fi

# Build RAG Server
echo "Building RAG Server image..."
docker build --platform linux/amd64 -f src/nvidia_rag/rag_server/Dockerfile -t $ECR_REGISTRY/$RAG_IMAGE:$IMAGE_TAG .
docker push $ECR_REGISTRY/$RAG_IMAGE:$IMAGE_TAG

# Build Ingestor Server  
echo "Building Ingestor Server image..."
docker build --platform linux/amd64 -f src/nvidia_rag/ingestor_server/Dockerfile -t $ECR_REGISTRY/$INGESTOR_IMAGE:$IMAGE_TAG .
docker push $ECR_REGISTRY/$INGESTOR_IMAGE:$IMAGE_TAG

echo "✅ Images built and pushed successfully!"
echo "RAG Server: $ECR_REGISTRY/$RAG_IMAGE:$IMAGE_TAG"
echo "Ingestor Server: $ECR_REGISTRY/$INGESTOR_IMAGE:$IMAGE_TAG"
