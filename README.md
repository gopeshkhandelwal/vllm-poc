# Design Studio Agent

AI-powered design studio with LLM inference and image generation on Intel XPU.

## Services

### vLLM Architect (Port 8001)
OpenAI-compatible LLM API running on Intel XPU.

- **Image**: `amr-registry.caas.intel.com/intelcloud/xpu-vllm-gil:1.0`
- **Model**: `openai/gpt-oss-20b` (MXFP4 quantized)
- **Endpoint**: `http://localhost:8001/v1`
- **GPU**: Intel Arc Pro B60 (single GPU)

### ComfyUI Flux (Port 3000)
Image generation service with ComfyUI backend.

### Orchestrator (Port 9000)
LangGraph-based orchestrator connecting LLM and image services.

## Quick Start

```bash
# Start all services
docker compose up -d

# Check vLLM status
curl http://localhost:8001/v1/models

# Test chat completion
curl http://localhost:8001/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "openai/gpt-oss-20b", "messages": [{"role": "user", "content": "Hello"}], "max_tokens": 50}'

# Check ComfyUI status
curl http://localhost:3000/
```

## Configuration

### vLLM Settings
| Setting | Value |
|---------|-------|
| Model | `openai/gpt-oss-20b` |
| Context Length | 65536 tokens |
| Precision | MXFP4 (quantized) |
| GPU Memory Utilization | 90% |

### Model Storage
- vLLM models: `./models/huggingface/`
- ComfyUI models: `./models/comfyui/`

Models are auto-downloaded on first startup.

## Environment Variables

| Variable | Description |
|----------|-------------|
| `HUGGING_FACE_HUB_TOKEN` | HuggingFace token for gated models |
| `MODEL_NAME` | Model name for orchestrator |

## Requirements

- Docker & Docker Compose
- Intel XPU with Level Zero drivers
- 16GB+ GPU memory

## Intel Harbor Registry Setup

The vLLM image is hosted on Intel's internal Harbor registry. First-time setup requires configuring Docker to trust the registry.

### 1. Configure NO_PROXY (Required)

Add `amr-registry.caas.intel.com` to Docker's NO_PROXY to bypass the Intel proxy:

Edit `/etc/systemd/system/docker.service.d/http-proxy.conf`:
```ini
[Service]
Environment="HTTP_PROXY=http://proxy-dmz.intel.com:912/"
Environment="HTTPS_PROXY=http://proxy-dmz.intel.com:912/"
Environment="NO_PROXY=10.0.0.0/8,intel.com,.intel.com,127.0.0.1,localhost,amr-registry.caas.intel.com,.caas.intel.com"
```

### 2. Install CA Certificate (Required)

Intel's Harbor registry uses an internal CA certificate that Docker doesn't trust by default.

```bash
# Extract certificate chain from registry
openssl s_client -connect amr-registry.caas.intel.com:443 -showcerts </dev/null 2>/dev/null | \
  awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/{ print }' > /tmp/amr-registry-chain.crt

# Install for Docker
sudo mkdir -p /etc/docker/certs.d/amr-registry.caas.intel.com
sudo cp /tmp/amr-registry-chain.crt /etc/docker/certs.d/amr-registry.caas.intel.com/ca.crt

# Also add to system trust store (recommended)
sudo cp /tmp/amr-registry-chain.crt /usr/local/share/ca-certificates/intel-amr-registry.crt
sudo update-ca-certificates
```

### 3. Restart Docker and Pull

```bash
sudo systemctl daemon-reload
sudo systemctl restart docker

# Pull the image
docker pull amr-registry.caas.intel.com/intelcloud/xpu-vllm-gil:1.0
```

### Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| `context deadline exceeded` | Proxy blocking registry | Add to NO_PROXY, restart Docker |
| `certificate signed by unknown authority` | Missing CA certificate | Install certificate chain (step 2) |
| `403 Forbidden` | Proxy intercepting request | Verify NO_PROXY includes the registry |