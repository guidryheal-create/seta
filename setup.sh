#!/bin/bash
# 1. install miniforge
SCRIPT_PATH=$(realpath "$0")
PROJECT_DIR=$(dirname "$SCRIPT_PATH")

# Check if conda is already installed
if command -v conda &> /dev/null
then
  echo "Conda already installed, skipping Miniforge installation."
  CONDA_BASE="$(conda info --base)"
  source ${CONDA_BASE}/bin/activate
else
  echo "Conda not found, installing Miniforge..."
  cd $PROJECT_DIR/../
  curl -L -O "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-$(uname)-$(uname -m).sh"
  bash Miniforge3-$(uname)-$(uname -m).sh -b
  CONDA_BASE="$HOME/miniforge3"
  source ${CONDA_BASE}/bin/activate
fi

# Create or activate seta environment
if conda env list | grep -q "^seta "; then
  echo "Environment 'seta' already exists, activating..."
else
  echo "Creating environment 'seta'..."
  conda create -n seta python=3.12 -y
fi

echo "Activating environment 'seta'..."
conda activate seta

# Install uv if not already installed
if ! command -v uv &> /dev/null
then
  pip install uv
fi
# 2. install dependencies
# if nvcc is not found, install cuda toolkit
if ! command -v nvcc &> /dev/null
then
    echo "nvcc not found, installing CUDA toolkit..."
    mamba install nvidia::cuda-toolkit -y
else
    echo "nvcc found, skipping CUDA toolkit installation."
fi

cd ${PROJECT_DIR}/external/camel && uv pip install --system -e .
cd ${PROJECT_DIR}/external/terminal-bench && uv pip install --system -e .
cd ${PROJECT_DIR}/external/AReaL && uv pip install --system -e .[all]

uv pip install --system flash-attn==2.8.3
uv pip install --system -U datasets transformers
uv pip install --system "numpy<2.3,>=2.0"

# 3. install docker if not found
if ! command -v docker &> /dev/null
then
    echo "Docker not found, installing..."
    cd ${PROJECT_DIR}/../
    # install docker using the convenience script
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh ./get-docker.sh
    # add current user to docker group
    sudo usermod -aG docker $USER
    newgrp docker
else
    echo "Docker found, skipping installation."
fi


# 4. modify docker to increase network address pool

DOCKER_DAEMON_CONFIG='/etc/docker/daemon.json'

# Backup existing daemon.json if it exists
if [ -f "$DOCKER_DAEMON_CONFIG" ]; then
    echo "Backing up existing Docker daemon configuration..."
    sudo cp "$DOCKER_DAEMON_CONFIG" "${DOCKER_DAEMON_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Create or update daemon.json with network pool settings
echo "Configuring Docker daemon..."
sudo tee "$DOCKER_DAEMON_CONFIG" > /dev/null <<EOF
{
  "default-address-pools": [
    {
      "base": "10.200.0.0/16",
      "size": 24
    }
  ]
}
EOF

# Restart Docker to apply changes
echo "Restarting Docker daemon..."
sudo systemctl restart docker

echo "Docker configuration complete!"
