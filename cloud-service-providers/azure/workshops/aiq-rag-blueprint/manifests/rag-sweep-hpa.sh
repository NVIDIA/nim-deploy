#!/usr/bin/env bash
# shfmt -i 2 -ci -w

# Script to sweep through different concurrency levels for RAG service with HPA
# Requires genai-perf CLI tool installed and configured
# Original author(s): Juana Nakfour,  Anita Tragler, Ruchika Kharwar, NVIDIA Corp.
# Original source: https://developer.nvidia.com/blog/enabling-horizontal-autoscaling-of-enterprise-rag-components-on-kubernetes/
# Modified by: Diego Casati, Microsoft Corp.

set -Eo pipefail

export RAG_SERVICE="rag-server:8081" #rag-server:port
export NIM_MODEL="nvidia/llama-3.3-nemotron-super-49b-v1.5" 
export NIM_MODEL_NAME="llama-3_3-nemotron-super-49b-v1.5" 
export NIM_MODEL_TOKENIZER="nvidia/Llama-3_3-Nemotron-Super-49B-v1" 
 
export CONCURRENCY_RANGE="50 100 150 200 250 300" #loop through the concurrency range to autoscale nim-llm
export request_multiplier=15 #number of requests per concurrency
 
#RAG specific parameters sent to rag-server
export ISL="256" # Input Sequence Length (ISL) inputs to sweep over
export OSL="256" # Output Sequence Length (OSL) inputs to sweep over
 
export COLLECTION="multimodal_data"
export VDB_TOPK=10
export RERANKER_TOPK=4
export OUTPUT_DIR="../results"
 
for CR in ${CONCURRENCY_RANGE}; do
 
  total_requests=$((request_multiplier * CR))
  EXPORT_FILE=RAG_CR-${CR}_ISL-${ISL}_OSL-${OSL}-$(date +"%Y-%m-%d-%H_%M_%S").json
 
  START_TIME=$(date +%s)
  genai-perf profile \
    -m $NIM_MODEL_NAME \
    --endpoint-type chat \
    --streaming -u $RAG_SERVICE \
    --request-count $total_requests \
    --synthetic-input-tokens-mean $ISL \
    --synthetic-input-tokens-stddev 0 \
    --concurrency $CR \
    --output-tokens-mean $OSL \
    --extra-inputs max_tokens:$OSL \
    --extra-inputs min_tokens:$OSL \
    --extra-inputs ignore_eos:true \
    --extra-inputs collection_name:$COLLECTION \
    --extra-inputs enable_reranker:true \
    --extra-inputs enable_citations:false \
    --extra-inputs enable_query_rewriting:false \
    --extra-inputs vdb_top_k:$VDB_TOPK \
    --extra-inputs reranker_top_k:$RERANKER_TOPK \
    --artifact-dir $OUTPUT_DIR \
    --tokenizer $MODEL \
    --profile-export-file $EXPORT_FILE \
    -- -v --max-threads=$CR
  END_TIME=$(date +%s)
  elapsed_time=$((END_TIME - START_TIME))
   
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] Completed: $EXPORT_FILE in $elapsed_time seconds"
done