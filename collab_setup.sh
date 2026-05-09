#!/usr/bin/env bash
set -eo pipefail

# ============================================================
# Google Colab setup script
# - Optimized for Colab GPU runtimes
# - Avoids Conda entirely
# - Uses system Python + uv
# - Safe to rerun (idempotent)
# ============================================================

# ------------------------------------------------------------
# Resolve project dir safely
# ------------------------------------------------------------

if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
    PROJECT_DIR="$(dirname "$SCRIPT_PATH")"
else
    PROJECT_DIR="$(pwd)"
fi

echo "============================================================"
echo "PROJECT_DIR=${PROJECT_DIR}"
echo "============================================================"

# ------------------------------------------------------------
# Helper
# ------------------------------------------------------------

run_safe () {
    "$@" || {
        echo "WARNING: command failed:"
        echo "  $*"
    }
}

# ============================================================
# 1. Python / uv setup
# ============================================================

echo
echo "============================================================"
echo "Installing uv + base tooling..."
echo "============================================================"

python -m pip install -U pip setuptools wheel
python -m pip install -U uv

# ============================================================
# 2. GPU / CUDA checks
# ============================================================

echo
echo "============================================================"
echo "Checking GPU runtime..."
echo "============================================================"

if command -v nvidia-smi &>/dev/null; then
    echo "GPU detected:"
    nvidia-smi
else
    echo "WARNING: No GPU runtime detected."
    echo "In Colab:"
    echo "  Runtime -> Change runtime type -> GPU"
fi

echo
echo "Checking nvcc..."

if command -v nvcc &>/dev/null; then
    nvcc --version
else
    echo "nvcc not found."
    echo "This is normal on Colab."
    echo "PyTorch CUDA wheels still work without nvcc."
fi

# ============================================================
# 3. Install ML stack first
# Prevent dependency thrashing
# ============================================================

echo
echo "============================================================"
echo "Installing ML dependencies..."
echo "============================================================"

uv pip install --system \
    "numpy>=1.26,<2.3" \
    "datasets>=2.18,<4.0" \
    "transformers>=4.46,<4.58"

# ------------------------------------------------------------
# Verify torch
# ------------------------------------------------------------

echo
echo "============================================================"
echo "Checking PyTorch CUDA..."
echo "============================================================"

python - <<'PY'
import torch

print("Torch version:", torch.__version__)
print("CUDA available:", torch.cuda.is_available())
print("Torch CUDA version:", torch.version.cuda)

if torch.cuda.is_available():
    print("GPU:", torch.cuda.get_device_name(0))
PY

# ============================================================
# 4. Install editable local packages
# ============================================================

echo
echo "============================================================"
echo "Installing editable project packages..."
echo "============================================================"

install_editable () {
    local path="$1"

    if [[ -d "$path" ]]; then
        echo
        echo "Installing: $path"

        cd "$path"
        uv pip install --system -e .
    else
        echo "WARNING: Missing directory: $path"
    fi
}

install_editable "${PROJECT_DIR}/external/camel"
install_editable "${PROJECT_DIR}/external/terminal-bench"

# AReaL uses extras
if [[ -d "${PROJECT_DIR}/external/AReaL" ]]; then
    echo
    echo "Installing: ${PROJECT_DIR}/external/AReaL"

    cd "${PROJECT_DIR}/external/AReaL"
    uv pip install --system -e ".[all]"
else
    echo "WARNING: Missing directory: ${PROJECT_DIR}/external/AReaL"
fi

# ============================================================
# 5. flash-attn
# Only if CUDA torch is available
# ============================================================

echo
echo "============================================================"
echo "Attempting flash-attn install..."
echo "============================================================"

if python - <<'PY'
import torch
raise SystemExit(0 if torch.cuda.is_available() else 1)
PY
then
    run_safe uv pip install --system \
        flash-attn==2.8.3 \
        --no-build-isolation
else
    echo "CUDA unavailable; skipping flash-attn."
fi

# ============================================================
# 6. Docker
# Colab does NOT support systemd properly
# We manually launch dockerd if needed
# ============================================================

echo
echo "============================================================"
echo "Checking Docker..."
echo "============================================================"

if command -v docker &>/dev/null; then
    echo "Docker already installed:"
    docker --version
else
    echo "Installing Docker..."

    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh

    echo "Docker installation complete."
fi

# ------------------------------------------------------------
# Start daemon manually
# ------------------------------------------------------------

if docker info >/dev/null 2>&1; then
    echo "Docker daemon already running."
else
    echo "Starting Docker daemon manually..."

    nohup dockerd \
        > /tmp/dockerd.log \
        2>&1 &

    sleep 15
fi

# ------------------------------------------------------------
# Verify Docker
# ------------------------------------------------------------

echo
echo "============================================================"
echo "Verifying Docker..."
echo "============================================================"

if docker info >/dev/null 2>&1; then
    echo "Docker is running."
else
    echo "WARNING: Docker failed to start."
    echo
    echo "Inspect logs with:"
    echo "  cat /tmp/dockerd.log"
fi

# ============================================================
# 7. Final environment verification
# ============================================================

echo
echo "============================================================"
echo "Final environment verification"
echo "============================================================"

python - <<'PY'
import sys

print("Python:", sys.version)

try:
    import torch
    print("Torch:", torch.__version__)
    print("CUDA:", torch.cuda.is_available())
except Exception as e:
    print("Torch check failed:", e)

try:
    import transformers
    print("Transformers:", transformers.__version__)
except Exception as e:
    print("Transformers check failed:", e)

try:
    import datasets
    print("Datasets:", datasets.__version__)
except Exception as e:
    print("Datasets check failed:", e)
PY

echo
echo "============================================================"
echo "Colab setup complete."
echo "============================================================"
