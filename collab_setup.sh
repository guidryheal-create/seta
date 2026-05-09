#!/usr/bin/env bash
set -e

# ============================================================
# Google Colab setup script
# - Assumes Ubuntu-based Colab runtime
# - Docker is usually preinstalled
# - CUDA runtime already exists on GPU runtimes
# - Avoids conda unless explicitly needed
# ============================================================

# Resolve project dir safely in Colab / notebooks
if [[ -n "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
    PROJECT_DIR="$(dirname "$SCRIPT_PATH")"
else
    PROJECT_DIR="$(pwd)"
fi

echo "PROJECT_DIR=${PROJECT_DIR}"

# ============================================================
# 1. Python / uv setup
# ============================================================

echo "Installing uv..."

python -m pip install -U pip setuptools wheel
python -m pip install -U uv

# ============================================================
# 2. CUDA check
# Colab GPU runtimes already include CUDA.
# We only verify availability.
# ============================================================

if command -v nvidia-smi &> /dev/null; then
    echo "GPU detected:"
    nvidia-smi
else
    echo "WARNING: No GPU runtime detected."
    echo "In Colab: Runtime -> Change runtime type -> GPU"
fi

if command -v nvcc &> /dev/null; then
    echo "nvcc found:"
    nvcc --version
else
    echo "nvcc not found."
    echo "This is normal on some Colab runtimes."
    echo "PyTorch CUDA wheels should still work."
fi

# ============================================================
# 3. Install project dependencies
# ============================================================

echo "Installing editable packages..."

cd "${PROJECT_DIR}/external/camel"
uv pip install --system -e .

cd "${PROJECT_DIR}/external/terminal-bench"
uv pip install --system -e .

cd "${PROJECT_DIR}/external/AReaL"
uv pip install --system -e ".[all]"

# ============================================================
# 4. PyTorch / CUDA packages
# ============================================================

echo "Installing ML dependencies..."

uv pip install --system -U datasets transformers
uv pip install --system "numpy>=2.0,<2.3"

# flash-attn:
# Only install if GPU + compatible CUDA toolchain exists
if command -v nvidia-smi &> /dev/null; then
    echo "Attempting flash-attn install..."

    # torch should already exist in Colab,
    # but upgrade if desired:
    python -c "import torch; print(torch.__version__)"

    uv pip install --system flash-attn==2.8.3 --no-build-isolation || \
    echo "flash-attn install failed; continuing..."
fi

# ============================================================
# 5. Docker
# Colab usually already has Docker installed.
# We avoid daemon reconfiguration because:
# - systemd is restricted in Colab
# - daemon.json edits often fail
# ============================================================

if command -v docker &> /dev/null; then
    echo "Docker already installed:"
    docker --version
else
    echo "Docker not found. Installing..."

    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh

    echo "Docker installed."
fi

# ============================================================
# 6. Start Docker daemon manually (needed in Colab)
# ============================================================

if ! docker info >/dev/null 2>&1; then
    echo "Starting Docker daemon..."

    nohup dockerd > /tmp/dockerd.log 2>&1 &

    sleep 10
fi

# ============================================================
# 7. Verify Docker
# ============================================================

if docker info >/dev/null 2>&1; then
    echo "Docker is running."
else
    echo "Docker failed to start."
    echo "Check logs:"
    echo "cat /tmp/dockerd.log"
fi

echo "============================================================"
echo "Colab setup complete."
echo "============================================================"
