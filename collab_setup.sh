#!/usr/bin/env bash
set -eo pipefail

# ============================================================
# Google Colab setup script (fully rootless, Docker safe)
# ============================================================

# ------------------------------------------------------------
# Resolve project directory
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
# Helper function for safe commands
# ------------------------------------------------------------
run_safe () {
    "$@" || echo "WARNING: command failed: $*"
}

# ============================================================
# 1. Python / uv setup
# ============================================================
echo "Installing uv and base Python tooling..."
python -m pip install -U pip setuptools wheel
python -m pip install -U uv

# ============================================================
# 2. GPU / CUDA checks
# ============================================================
echo "Checking GPU..."
if command -v nvidia-smi &>/dev/null; then
    echo "GPU detected:"
    nvidia-smi
else
    echo "WARNING: No GPU runtime detected."
fi

echo "Checking nvcc..."
if command -v nvcc &>/dev/null; then
    nvcc --version
else
    echo "nvcc not found. Normal on Colab; CUDA PyTorch still works."
fi

# ============================================================
# 3. ML dependencies
# ============================================================
echo "Installing ML stack..."
uv pip install --system \
    "numpy>=1.26,<2.3" \
    "datasets>=2.18,<4.0" \
    "transformers>=4.46,<4.58"

# ------------------------------------------------------------
# Verify PyTorch
# ------------------------------------------------------------
python - <<'PY'
import torch
print("Torch version:", torch.__version__)
print("CUDA available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("GPU:", torch.cuda.get_device_name(0))
PY

# ============================================================
# 4. Editable local packages
# ============================================================
install_editable () {
    local path="$1"
    if [[ -d "$path" ]]; then
        echo "Installing editable package: $path"
        cd "$path"
        uv pip install --system -e .
    else
        echo "WARNING: Missing directory: $path"
    fi
}

install_editable "${PROJECT_DIR}/external/camel"
install_editable "${PROJECT_DIR}/external/terminal-bench"

if [[ -d "${PROJECT_DIR}/external/AReaL" ]]; then
    echo "Installing AReaL with extras..."
    cd "${PROJECT_DIR}/external/AReaL"
    uv pip install --system -e ".[all]"
else
    echo "WARNING: Missing directory: ${PROJECT_DIR}/external/AReaL"
fi

# ============================================================
# 5. flash-attn (CUDA only)
# ============================================================
if python - <<'PY'
import torch
raise SystemExit(0 if torch.cuda.is_available() else 1)
PY
then
    run_safe uv pip install --system flash-attn==2.8.3 --no-build-isolation
else
    echo "CUDA unavailable; skipping flash-attn."
fi

# ============================================================
# 6. Rootless Docker
# ============================================================
echo "Setting up rootless Docker..."
if command -v docker &>/dev/null; then
    echo "Docker already installed:"
    docker --version
else
    curl -fsSL https://get.docker.com/rootless -o /tmp/get-docker-rootless.sh
    sh /tmp/get-docker-rootless.sh
fi

# Start rootless Docker daemon manually
if ! docker info >/dev/null 2>&1; then
    echo "Starting rootless Docker..."
    export XDG_RUNTIME_DIR=/tmp/docker-rootless
    mkdir -p "$XDG_RUNTIME_DIR"
    nohup dockerd-rootless.sh > /tmp/dockerd-rootless.log 2>&1 &
    export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock
    sleep 10
fi

# Verify Docker
if docker info >/dev/null 2>&1; then
    echo "Docker is running (rootless)."
else
    echo "WARNING: Docker failed to start. Check logs:"
    echo "cat /tmp/dockerd-rootless.log"
fi

# ============================================================
# 7. Final verification
# ============================================================
python - <<'PY'
import sys
print("Python:", sys.version)

for pkg in ["torch", "transformers", "datasets"]:
    try:
        mod = __import__(pkg)
        print(f"{pkg}: {mod.__version__}")
    except Exception as e:
        print(f"{pkg} check failed:", e)

try:
    import torch
    print("CUDA available:", torch.cuda.is_available())
except Exception as e:
    print("CUDA check failed:", e)
PY

echo "============================================================"
echo "Colab setup complete. Rootless Docker ready."
echo "============================================================"
