#!/bin/bash

# Local testing script for the tester image
# Usage: ./test-local.sh [repo-url] [commit-hash] [image-tag]

set -e

# Default values
REPO_URL="${1:-https://github.com/example/java-project.git}"
COMMIT_HASH="${2:-HEAD}"
IMAGE_TAG="${3:-thesis-tester:latest}"

echo "🧪 Testing tester image locally"
echo "Repository: $REPO_URL"
echo "Commit: $COMMIT_HASH"
echo "Image: $IMAGE_TAG"
echo "================================"

# Create temp directories for outputs
TEMP_DIR=$(mktemp -d)
RESULTS_DIR="$TEMP_DIR/results"
LOGS_DIR="$TEMP_DIR/logs"

mkdir -p "$RESULTS_DIR" "$LOGS_DIR"

echo "📁 Output directories:"
echo "  Results: $RESULTS_DIR"
echo "  Logs: $LOGS_DIR"
echo ""

# Run the tester container
echo "🚀 Running tester container..."
echo "================================"

# Capture both stdout (JSON result) and stderr (logs)
if docker run --rm \
  -e GRADING_JOB_ID=123 \
  -e REPO_URL="$REPO_URL" \
  -e GIT_COMMIT_HASH="$COMMIT_HASH" \
  -e OUTPUT_FORMAT=json \
  -e TIMEOUT_SECONDS=300 \
  -v "$RESULTS_DIR:/results" \
  -v "$LOGS_DIR:/logs" \
  "$IMAGE_TAG" > "$TEMP_DIR/output.json" 2> "$TEMP_DIR/logs.txt"; then
  
  echo "✅ Container execution completed successfully"
  echo ""
  
  # Show the JSON result
  if [[ -f "$TEMP_DIR/output.json" ]] && [[ -s "$TEMP_DIR/output.json" ]]; then
    echo "📋 Test Results (JSON):"
    echo "======================="
    cat "$TEMP_DIR/output.json" | jq . || cat "$TEMP_DIR/output.json"
    echo ""
  else
    echo "❌ No JSON output found"
  fi
  
  # Show execution logs
  if [[ -f "$TEMP_DIR/logs.txt" ]] && [[ -s "$TEMP_DIR/logs.txt" ]]; then
    echo "📝 Execution Logs:"
    echo "=================="
    cat "$TEMP_DIR/logs.txt"
    echo ""
  fi
  
else
  echo "❌ Container execution failed"
  echo ""
  
  # Show error logs
  if [[ -f "$TEMP_DIR/logs.txt" ]]; then
    echo "🚨 Error Logs:"
    echo "=============="
    cat "$TEMP_DIR/logs.txt"
    echo ""
  fi
  
  # Show any output that might have been produced
  if [[ -f "$TEMP_DIR/output.json" ]]; then
    echo "📄 Output (if any):"
    echo "==================="
    cat "$TEMP_DIR/output.json"
    echo ""
  fi
fi

# Show summary
echo "📊 Test Summary:"
echo "================"
echo "Repository: $REPO_URL"
echo "Image: $IMAGE_TAG"
echo "Temp dir: $TEMP_DIR"
echo ""

# Ask if user wants to keep temp files
read -p "🗑️  Clean up temporary files? (y/N): " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$TEMP_DIR"
    echo "🧹 Cleaned up temporary files"
else
    echo "📁 Temporary files kept at: $TEMP_DIR"
fi

echo ""
echo "🎉 Local testing completed!" 