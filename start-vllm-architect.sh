#!/bin/bash
set -euo pipefail

# =============================================================
# vLLM Architect Startup Script
# Intel XPU vLLM for Arc Pro B60 GPUs
# OpenAI-compatible API at http://localhost:8001/v1
# =============================================================

MODEL_ID="openai/gpt-oss-120b"
MODEL_LOCAL_PATH="/llm/models/openai/gpt-oss-120b"
SERVED_MODEL_NAME="openai/gpt-oss-120b"

echo "=== vLLM Architect Startup ==="
echo "Model: $MODEL_ID"
echo "Path: $MODEL_LOCAL_PATH"

# Download model if missing (exclude original/ and metal/ folders to save space)
if [ ! -f "$MODEL_LOCAL_PATH/config.json" ]; then
    echo "=== Downloading model (excluding original/ and metal/) ==="
    python -c "
from huggingface_hub import snapshot_download
snapshot_download(
    repo_id='$MODEL_ID',
    local_dir='$MODEL_LOCAL_PATH',
    ignore_patterns=['original/*', 'metal/*']
)
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

# Create chat template that instructs model to skip reasoning
cat > /llm/chat_template.jinja << 'TEMPLATE'
{%- if messages and messages[0]['role'] == 'system' -%}
{{ messages[0]['content'] }}

{%- set messages = messages[1:] -%}
{%- endif %}

{%- for message in messages %}
{%- if message['role'] == 'user' %}
User: {{ message['content'] }}

{%- elif message['role'] == 'assistant' %}
Assistant: {{ message['content'] }}

{%- endif %}
{%- endfor %}

Assistant: IMPORTANT:
- Return ONLY the final answer.
- Do NOT include analysis, reasoning, or thinking steps.
- Start immediately with the requested section headings or content.
- Do not add preambles or summaries unless explicitly requested.
- If the answer is long, provide a concise but complete response rather than reasoning.
TEMPLATE

echo "=== Starting vLLM server on port 8001 ==="

# vLLM serve configuration:
# --enforce-eager: Disable torch.compile to avoid RPC timeouts
# --max-model-len 16384: Reduced context for faster KV cache allocation
vllm serve "$MODEL_LOCAL_PATH" \
    --served-model-name "$SERVED_MODEL_NAME" \
    --host 0.0.0.0 \
    --port 8001 \
    --tensor-parallel-size 4 \
    --max-model-len 16384 \
    --gpu-memory-utilization 0.9 \
    --quantization mxfp4 \
    --trust-remote-code \
    --enable-prefix-caching \
    --enforce-eager \
    --chat-template /llm/chat_template.jinja \
    2>&1 | tee /llm/logs/vllm-metrics.log &

VLLM_PID=$!

# Warmup: wait for server and send test requests (10 minutes timeout for large models)
echo "=== Waiting for vLLM to be ready (showing live progress) ==="
SERVER_READY=false
LAST_LOG_LINES=0
for i in {1..250}; do
    if curl -s http://localhost:8001/v1/models > /dev/null 2>&1; then
        echo ""
        echo "=========================================="
        echo "vLLM is ready. Running warmup..."
        SERVER_READY=true
        break
    fi
    if ! kill -0 $VLLM_PID 2>/dev/null; then
        echo "ERROR: vLLM process died unexpectedly"
        echo "=== Last 50 log lines ==="
        tail -50 /llm/logs/vllm-metrics.log
        exit 1
    fi
    # Show new log lines since last check
    CURRENT_LINES=$(wc -l < /llm/logs/vllm-metrics.log 2>/dev/null || echo 0)
    if [ "$CURRENT_LINES" -gt "$LAST_LOG_LINES" ]; then
        tail -n +$((LAST_LOG_LINES + 1)) /llm/logs/vllm-metrics.log | head -50
        LAST_LOG_LINES=$CURRENT_LINES
    fi
    sleep 5
done

if [ "$SERVER_READY" = false ]; then
    echo "ERROR: Server failed to start within timeout (5 minutes)"
    kill $VLLM_PID 2>/dev/null || true
    echo "Check logs at /llm/logs/vllm-metrics.log"
    exit 1
fi

echo "=== Running warmup requests ==="
for i in {1..3}; do
    curl -s http://localhost:8001/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$SERVED_MODEL_NAME\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}], \"max_tokens\": 16}" \
        > /dev/null 2>&1
    echo "Warmup $i/3"
done

echo "=== Warmup complete. Server ready ==="
wait $VLLM_PID
