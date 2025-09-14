#!/bin/bash
#────────────────────────────────────────────────────────────
#  🔨 BUILD CUSTOM DEVELOPMENT IMAGE
#────────────────────────────────────────────────────────────

set -e

echo "🏗️ Building custom development image..."

# Image name and tag
IMAGE_NAME="localhost/vscode-dev-custom"
IMAGE_TAG="latest"

# Create build directory if it doesn't exist
mkdir -p ~/podman_data/vscode/image

# Copy Dockerfile to build directory
cp Dockerfile ~/podman_data/vscode/image/

# Build the image
echo "🔨 Building image: $IMAGE_NAME:$IMAGE_TAG"
podman build -t "$IMAGE_NAME:$IMAGE_TAG" ~/podman_data/vscode/image/

# Show image info
echo ""
echo "✅ Image built successfully!"
podman images | grep vscode-dev-custom

echo ""
echo "📦 Image includes:"
echo "   ✅ LinuxServer code-server base"
echo "   ✅ Python 3 + pip + venv"
echo "   ✅ Jupyter Lab/Notebook + pandas + numpy + matplotlib"
echo "   ✅ Java (8, 11, 17, 21) via SDKMAN"
echo "   ✅ Maven, Gradle, SBT"
echo "   ✅ LaTeX (texlive full)"
echo "   ✅ Node.js + npm"
echo "   ✅ Go programming language"
echo "   ✅ VS Code extensions pre-installed"
echo "   ✅ Conda for environment management"
echo ""
echo "🚀 Ready to use in your pod deployment!"
