#!/bin/bash
set -euo pipefail

# =============================================================
# vLLM Architect Startup Script
# Intel XPU vLLM for Arc Pro B60 GPUs
# OpenAI-compatible API at http://localhost:8001/v1
# =============================================================

MODEL_ID="mistralai/Ministral-8B-Instruct-2410"
MODEL_LOCAL_PATH="/llm/models/mistralai/Ministral-8B-Instruct-2410"
SERVED_MODEL_NAME="mistralai/Ministral-8B-Instruct-2410"

echo "=== vLLM Architect Startup ==="
echo "Model: $MODEL_ID"
echo "Path: $MODEL_LOCAL_PATH"

# Download model if missing
if [ ! -d "$MODEL_LOCAL_PATH" ] || [ -z "$(ls -A "$MODEL_LOCAL_PATH" 2>/dev/null)" ]; then
    echo "=== Downloading model ==="
    python -c "
from huggingface_hub import snapshot_download
snapshot_download(repo_id='$MODEL_ID', local_dir='$MODEL_LOCAL_PATH')
"
    echo "Download complete."
else
    echo "Model exists. Skipping download."
fi

# Verify model
if [ ! -f "$MODEL_LOCAL_PATH/config.json" ]; then
    echo "ERROR: config.json not found"
    exit 1
fi

echo "=== Starting vLLM server on port 8001 ==="

exec vllm serve "$MODEL_LOCAL_PATH" \
    --served-model-name "$SERVED_MODEL_NAME" \
    --host 0.0.0.0 \
    --port 8001 \
    --tensor-parallel-size 1 \
    --max-model-len 4096 \
    --dtype bfloat16 \
    --gpu-memory-utilization 0.9 \
    --trust-remote-code \
    --enforce-eager
