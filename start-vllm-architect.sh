#!/bin/bash
set -euo pipefail

# =============================================================
# vLLM Startup Script
# Downloads model if missing, then starts OpenAI-compatible API
# =============================================================

MODEL_ID="Qwen/Qwen2.5-7B-Instruct"
MODEL_LOCAL_PATH="/llm/models/Qwen/Qwen2.5-7B-Instruct"
SERVED_MODEL_NAME="Qwen/Qwen2.5-7B-Instruct"

# Proxy settings for model download
export http_proxy="${http_proxy:-http://proxy-dmz.intel.com:912}"
export https_proxy="${https_proxy:-http://proxy-dmz.intel.com:912}"
export no_proxy="${no_proxy:-localhost,127.0.0.1}"

echo "=== vLLM Startup Script ==="
echo "Model ID: $MODEL_ID"
echo "Local Path: $MODEL_LOCAL_PATH"

# Check if model exists, download if missing
echo "=== Checking if model exists ==="
if [ ! -d "$MODEL_LOCAL_PATH" ] || [ -z "$(ls -A "$MODEL_LOCAL_PATH" 2>/dev/null)" ]; then
    echo "Model not found. Downloading $MODEL_ID from HuggingFace..."
    python -c "
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='$MODEL_ID',
    local_dir='$MODEL_LOCAL_PATH'
)
"
    echo "Model download complete."
else
    echo "Model already exists at $MODEL_LOCAL_PATH. Skipping download."
fi

# Verify model files exist
if [ ! -f "$MODEL_LOCAL_PATH/config.json" ]; then
    echo "ERROR: Model config.json not found. Download may have failed."
    exit 1
fi

echo "=== Starting vLLM OpenAI-compatible API server on port 8001 ==="
exec python -m vllm.entrypoints.openai.api_server \
    --model "$MODEL_LOCAL_PATH" \
    --served-model-name "$SERVED_MODEL_NAME" \
    --host 0.0.0.0 \
    --port 8001 \
    --tensor-parallel-size 1 \
    --max-model-len 1024 \
    --dtype bfloat16 \
    --enforce-eager
