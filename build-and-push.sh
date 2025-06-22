#!/bin/bash

# Build and push script for thesis-tester image
# Usage: ./build-and-push.sh [registry] [tag]

set -e

# Configuration
REGISTRY="${1:-ghcr.io/your-username}"
TAG="${2:-latest}"
IMAGE_NAME="thesis-tester"
FULL_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}:${TAG}"

echo "🔨 Building and pushing thesis-tester image"
echo "============================================"
echo "Registry: $REGISTRY"
echo "Tag: $TAG"
echo "Full image name: $FULL_IMAGE_NAME"
echo ""

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running or not accessible"
    exit 1
fi

# Build the image
echo "🏗️  Building Docker image..."
echo "============================="
if docker build -t "${IMAGE_NAME}:${TAG}" -t "${IMAGE_NAME}:latest" -t "$FULL_IMAGE_NAME" .; then
    echo "✅ Image built successfully"
else
    echo "❌ Failed to build image"
    exit 1
fi

echo ""

# Test the image locally first
echo "🧪 Testing image locally..."
echo "==========================="
if docker run --rm \
    -e GRADING_JOB_ID=test \
    -e REPO_URL="https://github.com/junit-team/junit4.git" \
    -e GIT_COMMIT_HASH="HEAD" \
    -e OUTPUT_FORMAT=json \
    -e TIMEOUT_SECONDS=60 \
    "${IMAGE_NAME}:${TAG}" --version > /dev/null 2>&1; then
    echo "✅ Image test passed"
else
    echo "⚠️  Image test failed, but continuing with push"
fi

echo ""

# Check if we should push
read -p "🚀 Push image to registry? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "📤 Pushing image to registry..."
    echo "==============================="
    
    # Push the image
    if docker push "$FULL_IMAGE_NAME"; then
        echo "✅ Image pushed successfully"
        echo ""
        echo "🎉 Image is now available at:"
        echo "   $FULL_IMAGE_NAME"
        echo ""
        echo "📋 To use this image in your thesis-llm service:"
        echo "   Update the tester-image configuration to:"
        echo "   tester-image: \"$FULL_IMAGE_NAME\""
    else
        echo "❌ Failed to push image"
        echo "💡 Make sure you're logged in to the registry:"
        echo "   docker login $REGISTRY"
        exit 1
    fi
else
    echo "⏭️  Skipping push"
    echo ""
    echo "🏠 Image built locally as:"
    echo "   ${IMAGE_NAME}:${TAG}"
    echo "   ${IMAGE_NAME}:latest"
    echo "   $FULL_IMAGE_NAME"
fi

echo ""
echo "📊 Build Summary:"
echo "================="
echo "Local tags:"
echo "  - ${IMAGE_NAME}:${TAG}"
echo "  - ${IMAGE_NAME}:latest"
echo "Registry tag:"
echo "  - $FULL_IMAGE_NAME"
echo ""

# Show image size
echo "📏 Image size:"
docker images "${IMAGE_NAME}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"

echo ""
echo "🎉 Build process completed!" 