# Build argument for base image selection
ARG BASE_IMAGE=nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04

# Stage 1: Base image with common dependencies
FROM ${BASE_IMAGE} AS base

# Build arguments for this stage with sensible defaults for standalone builds
ARG COMFYUI_VERSION=latest
ARG CUDA_VERSION_FOR_COMFY
ARG ENABLE_PYTORCH_UPGRADE=false
ARG PYTORCH_INDEX_URL

# Prevents prompts from packages asking for user input during installation
ENV DEBIAN_FRONTEND=noninteractive
# Prefer binary wheels over source distributions for faster pip installations
ENV PIP_PREFER_BINARY=1
# Ensures output from python is printed immediately to the terminal without buffering
ENV PYTHONUNBUFFERED=1
# Speed up some cmake builds
ENV CMAKE_BUILD_PARALLEL_LEVEL=8

# Install Python, git and other necessary tools
RUN apt-get update && apt-get install -y \
    python3.12 \
    python3.12-venv \
    git \
    wget \
    curl \
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender1 \
    ffmpeg \
    && ln -sf /usr/bin/python3.12 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip

# Clean up to reduce image size
RUN apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/*

# Install uv (latest) using official installer and create isolated venv
RUN wget -qO- https://astral.sh/uv/install.sh | sh \
    && ln -s /root/.local/bin/uv /usr/local/bin/uv \
    && ln -s /root/.local/bin/uvx /usr/local/bin/uvx \
    && uv venv /opt/venv

# Use the virtual environment for all subsequent commands
ENV PATH="/opt/venv/bin:${PATH}"

# Install comfy-cli + dependencies needed by it to install ComfyUI
RUN uv pip install comfy-cli pip setuptools wheel 


# Install ComfyUI
RUN if [ -n "${CUDA_VERSION_FOR_COMFY}" ]; then \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --cuda-version "${CUDA_VERSION_FOR_COMFY}" --nvidia; \
    else \
      /usr/bin/yes | comfy --workspace /comfyui install --version "${COMFYUI_VERSION}" --nvidia; \
    fi

# Upgrade PyTorch if needed (for newer CUDA versions)
RUN if [ "$ENABLE_PYTORCH_UPGRADE" = "true" ]; then \
      uv pip install --force-reinstall torch torchvision torchaudio --index-url ${PYTORCH_INDEX_URL}; \
    fi

# Change working directory to ComfyUI
WORKDIR /comfyui

# Support for the network volume
ADD src/extra_model_paths.yaml ./

# Install custom nodes
RUN cd custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && \
    cd ComfyUI-Impact-Pack && \
    uv pip install -r requirements.txt

RUN cd custom_nodes && \
    git clone https://github.com/ltdrdata/ComfyUI-Impact-Subpack.git && \
    cd ComfyUI-Impact-Subpack && \
    if [ -f requirements.txt ]; then uv pip install -r requirements.txt; fi

RUN cd custom_nodes && \
    git clone https://github.com/kijai/ComfyUI-KJNodes.git && \
    cd ComfyUI-KJNodes && \
    if [ -f requirements.txt ]; then uv pip install -r requirements.txt; fi

RUN cd custom_nodes && \
    git clone https://github.com/welltop-cn/ComfyUI-TeaCache.git && \
    cd ComfyUI-TeaCache && \
    if [ -f requirements.txt ]; then uv pip install -r requirements.txt; fi

RUN cd custom_nodes && \
    git clone https://github.com/cubiq/ComfyUI_essentials.git && \
    cd ComfyUI_essentials && \
    if [ -f requirements.txt ]; then uv pip install -r requirements.txt; fi

RUN cd custom_nodes && \
    git clone https://github.com/lquesada/ComfyUI-Inpaint-CropAndStitch.git && \
    cd ComfyUI-Inpaint-CropAndStitch && \
    if [ -f requirements.txt ]; then uv pip install -r requirements.txt; fi

RUN cd custom_nodes && \
    git clone https://github.com/rgthree/rgthree-comfy.git && \
    cd rgthree-comfy && \
    if [ -f requirements.txt ]; then uv pip install -r requirements.txt; fi

# RES4LYF - ClownSampler, T5TokenizerOptions, Sigmas Rescale, and advanced samplers
RUN cd custom_nodes && \
    git clone https://github.com/ClownsharkBatwing/RES4LYF.git && \
    cd RES4LYF && \
    if [ -f requirements.txt ]; then uv pip install -r requirements.txt; fi

# Install dependencies
RUN uv pip install segment-anything ultralytics

# Go back to the root
WORKDIR /

# Install Python runtime dependencies for the handler
RUN uv pip install runpod requests websocket-client

# Add application code and scripts
ADD src/start.sh handler.py test_input.json ./
RUN chmod +x /start.sh

# Add script to install custom nodes
COPY scripts/comfy-node-install.sh /usr/local/bin/comfy-node-install
RUN chmod +x /usr/local/bin/comfy-node-install

# Prevent pip from asking for confirmation during uninstall steps in custom nodes
ENV PIP_NO_INPUT=1

# Copy helper script to switch Manager network mode at container start
COPY scripts/comfy-manager-set-mode.sh /usr/local/bin/comfy-manager-set-mode
RUN chmod +x /usr/local/bin/comfy-manager-set-mode

# Set the default command to run when starting the container
CMD ["/start.sh"]

# Stage 2: Download models
FROM base AS downloader

# CivitAI access token for downloading models
ENV CIVITAI_ACCESS_TOKEN=fd049e4ad21d0da8bed9b3e4a117760e
# Set default model type if none is provided
ARG MODEL_TYPE=flux1-dev-fp8

# Change working directory to ComfyU
WORKDIR /comfyui

# Create necessary directories upfront
RUN mkdir -p models/checkpoints/Pony models/diffusion_models models/text_encoders models/vae models/sams models/ultralytics/bbox models/loras/Chroma

# ============================================
# CHROMA WORKFLOW MODELS - PARALLEL DOWNLOADS
# Cache bust: v2 - force rebuild 2024-12-18
# ============================================

# Download all large models in parallel using background processes
RUN echo "Downloading all models in parallel v2..." && \
    # Start all downloads in background
    curl -L -J -o models/diffusion_models/Chroma-DC-2K.safetensors "https://huggingface.co/silveroxides/Chroma-Misc-Models/resolve/main/Chroma-DC-2K/Chroma-DC-2K.safetensors" & \
    curl -L -J -o "models/checkpoints/Pony/gonzalomoXLFluxPony_v60PhotoXLDMD.safetensors" -H "Authorization: Bearer ${CIVITAI_ACCESS_TOKEN}" "https://civitai.com/api/download/models/2368123?type=Model&format=SafeTensor&size=pruned&fp=fp16" & \
    curl -L -J -o models/vae/FLUX.1-dev-vae.safetensors "https://huggingface.co/lovis93/testllm/resolve/ed9cf1af7465cebca4649157f118e331cf2a084f/ae.safetensors" & \
    curl -L -J -o models/text_encoders/t5xxl_fp16.safetensors "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors" & \
    wget -q -O models/sams/sam_vit_b_01ec64.pth https://dl.fbaipublicfiles.com/segment_anything/sam_vit_b_01ec64.pth & \
    wget -q -O models/ultralytics/bbox/face_yolov9c.pt "https://huggingface.co/Bingsu/adetailer/resolve/main/face_yolov9c.pt" & \
    # Wait for all background jobs
    wait && \
    echo "Large models downloaded:" && \
    ls -lh models/diffusion_models/ models/checkpoints/Pony/ models/vae/ models/text_encoders/ models/sams/ models/ultralytics/bbox/

# ============================================
# CHROMA LORAS - PARALLEL DOWNLOADS
# ============================================

# Download all LoRAs in parallel
RUN echo "Downloading all LoRAs in parallel..." && \
    curl -L -J -o "models/loras/Chroma/1518goontunerank64prodigy.safetensors" -H "Authorization: Bearer ${CIVITAI_ACCESS_TOKEN}" "https://civitai.com/api/download/models/2194938?type=Model&format=SafeTensor" & \
    curl -L -J -o "models/loras/Chroma/CHROMA_Absolute Cinema.safetensors" -H "Authorization: Bearer ${CIVITAI_ACCESS_TOKEN}" "https://civitai.com/api/download/models/2193551?type=Model&format=SafeTensor" & \
    curl -L -J -o "models/loras/Chroma/painal_v1.safetensors" -H "Authorization: Bearer ${CIVITAI_ACCESS_TOKEN}" "https://civitai.com/api/download/models/2244823?type=Model&format=SafeTensor" & \
    curl -L -J -o "models/loras/Chroma/chroma-unlocked-v47-flash-heun-8steps-cfg1_r96-fp32.safetensors" "https://huggingface.co/silveroxides/Chroma-LoRAs/resolve/main/flash-heun/chroma-unlocked-v47-flash-heun-8steps-cfg1_r96-fp32.safetensors" & \
    curl -L -J -o "models/loras/Chroma/lenovo_chroma.safetensors" -H "Authorization: Bearer ${CIVITAI_ACCESS_TOKEN}" "https://civitai.com/api/download/models/2299345?type=Model&format=SafeTensor" & \
    curl -L -J -o "models/loras/Chroma/- Chroma - profphotos_cinematic_atmo_3.0.safetensors" -H "Authorization: Bearer ${CIVITAI_ACCESS_TOKEN}" "https://civitai.com/api/download/models/2136912?type=Model&format=SafeTensor" & \
    wait && \
    echo "LoRAs downloaded:" && \
    ls -lh models/loras/Chroma/

# Stage 3: Final image
FROM base AS final

# Copy models from stage 2 to the final image
COPY --from=downloader /comfyui/models /comfyui/models

# Verify models are copied correctly
RUN echo "=== Chroma Diffusion Model ===" && \
    ls -lh /comfyui/models/diffusion_models/ && \
    echo "=== Pony Checkpoint (Refiner) ===" && \
    ls -lh /comfyui/models/checkpoints/Pony/ && \
    echo "=== VAE ===" && \
    ls -lh /comfyui/models/vae/ && \
    echo "=== Text Encoders ===" && \
    ls -lh /comfyui/models/text_encoders/ && \
    echo "=== SAM model ===" && \
    ls -lh /comfyui/models/sams/ && \
    echo "=== YOLO Face Detector ===" && \
    ls -lh /comfyui/models/ultralytics/bbox/ && \
    echo "=== Chroma LoRAs ===" && \
    ls -lh /comfyui/models/loras/Chroma/