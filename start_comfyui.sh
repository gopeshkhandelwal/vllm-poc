#!/bin/bash
set -e

# Define model paths
MODEL_DIR="/llm/ComfyUI/models"
export http_proxy="http://proxy-dmz.intel.com:912"
export https_proxy="http://proxy-dmz.intel.com:912"
export no_proxy="localhost,127.0.0.1"

echo "Checking model directories..."
mkdir -p "$MODEL_DIR/diffusion_models" \
         "$MODEL_DIR/text_encoders" \
         "$MODEL_DIR/vae" \
         "$MODEL_DIR/loras"

# Function to verify and download files
download_if_missing() {
    local url="$1"
    local dest="$2"
    
    if [ ! -f "$dest" ]; then
        echo "Downloading: $dest"
        if ! wget -q --show-progress "$url" -O "$dest"; then
            echo "Error: Failed to download $url"
            # Remove the destination file if wget failed to avoid keeping a corrupt partial file
            rm -f "$dest" 
            exit 1
        fi
    else
        echo "Found: $dest"
    fi
}

echo "Verifying FLUX.2 models..."

# FLUX.2 Dev FP8 Mixed
download_if_missing \
    "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/diffusion_models/flux2_dev_fp8mixed.safetensors" \
    "$MODEL_DIR/diffusion_models/flux2_dev_fp8mixed.safetensors"

# Mistral Text Encoder
download_if_missing \
    "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/text_encoders/mistral_3_small_flux2_bf16.safetensors" \
    "$MODEL_DIR/text_encoders/mistral_3_small_flux2_bf16.safetensors"

# LoRA
download_if_missing \
    "https://huggingface.co/ostris/flux2_berthe_morisot/resolve/main/flux2_berthe_morisot.safetensors" \
    "$MODEL_DIR/loras/flux2_berthe_morisot.safetensors"

# VAE
download_if_missing \
    "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors" \
    "$MODEL_DIR/vae/flux2-vae.safetensors"

echo "Starting ComfyUI..."
cd /llm/ComfyUI
exec python3 main.py --listen 0.0.0.0 --port 3000