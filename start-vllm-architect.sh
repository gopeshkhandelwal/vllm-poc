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

# vLLM serve configuration:
vllm serve "$MODEL_LOCAL_PATH" \
    --served-model-name "$SERVED_MODEL_NAME" \
    --host 0.0.0.0 \
    --port 8001 \
    --max-model-len 65536 \
    --gpu-memory-utilization 0.9 \
    --trust-remote-code \
    --enable-prefix-caching \
    2>&1 | tee /llm/logs/vllm-metrics.log &

VLLM_PID=$!

# Warmup: wait for server and send test requests
echo "=== Waiting for vLLM to be ready ==="
SERVER_READY=false
for i in {1..60}; do
    if curl -s http://localhost:8001/v1/models > /dev/null 2>&1; then
        echo "vLLM is ready. Running warmup..."
        SERVER_READY=true
        break
    fi
    # Check if vLLM process is still running
    if ! kill -0 $VLLM_PID 2>/dev/null; then
        echo "ERROR: vLLM process died unexpectedly"
        echo "Check logs at /llm/logs/vllm-metrics.log"
        exit 1
    fi
    echo "Waiting for server... ($i/60)"
    sleep 5
done

# Exit if server never became ready
if [ "$SERVER_READY" = false ]; then
    echo "ERROR: Server failed to start within timeout (5 minutes)"
    kill $VLLM_PID 2>/dev/null || true
    echo "Check logs at /llm/logs/vllm-metrics.log"
    exit 1
fi

# Send warmup requests to trigger JIT compilation and graph capture
echo "=== Running warmup requests ==="

# Short prompt warmup (3 requests)
for i in {1..3}; do
    curl -s http://localhost:8001/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$SERVED_MODEL_NAME\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}], \"max_tokens\": 16}" \
        > /dev/null 2>&1
    echo "Short prompt warmup $i/3"
done

# Medium prompt warmup (3 requests)
MEDIUM_PROMPT="You are a helpful assistant. Please explain the concept of machine learning in simple terms."
for i in {1..3}; do
    curl -s http://localhost:8001/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$SERVED_MODEL_NAME\", \"messages\": [{\"role\": \"user\", \"content\": \"$MEDIUM_PROMPT\"}], \"max_tokens\": 64}" \
        > /dev/null 2>&1
    echo "Medium prompt warmup $i/3"
done

# Longer output warmup (2 requests)
for i in {1..2}; do
    curl -s http://localhost:8001/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$SERVED_MODEL_NAME\", \"messages\": [{\"role\": \"user\", \"content\": \"Write a short paragraph about software architecture.\"}], \"max_tokens\": 128}" \
        > /dev/null 2>&1
    echo "Long output warmup $i/2"
done

echo "=== Warmup complete (8 requests). Server ready for production traffic ==="

# Keep the server running in foreground
wait $VLLM_PID
