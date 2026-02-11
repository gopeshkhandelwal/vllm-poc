#!/bin/bash
set -euo pipefail

# =============================================================
# vLLM Architect Startup Script
# Intel XPU vLLM for Arc Pro B60 GPUs
# OpenAI-compatible API at http://localhost:8001/v1
# =============================================================

MODEL_ID="openai/gpt-oss-20b"
MODEL_LOCAL_PATH="/llm/models/openai/gpt-oss-20b"
SERVED_MODEL_NAME="openai/gpt-oss-20b"

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

# Log metrics: Memory, CPU, KV-cache stats
# MXFP4 quantized 20B model fits on 1 GPU (~10-12GB)
vllm serve "$MODEL_LOCAL_PATH" \
    --served-model-name "$SERVED_MODEL_NAME" \
    --host 0.0.0.0 \
    --port 8001 \
    --tensor-parallel-size 1 \
    --max-model-len 4096 \
    --gpu-memory-utilization 0.85 \
    --trust-remote-code \
    --enforce-eager \
    --enable-prefix-caching \
    2>&1 | tee /llm/logs/vllm-metrics.log
