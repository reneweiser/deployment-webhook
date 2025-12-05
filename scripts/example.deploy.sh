#!/bin/bash
set -e  # Exit on any error

# Get arguments passed from webhook
COMMIT_ID="$1"
REPO_NAME="$2"
BRANCH_REF="$3"

# Log deployment start
echo "====================================="
echo "Deployment triggered at $(date)"
echo "Repository: $REPO_NAME"
echo "Branch: $BRANCH_REF"
echo "Commit: $COMMIT_ID"
echo "Target Path: $TARGET_REPO_PATH"
echo "Target Service: $TARGET_SERVICE_NAME"
echo "====================================="

# Navigate to the target repository
cd "$TARGET_REPO_PATH" || {
    echo "ERROR: Failed to navigate to $TARGET_REPO_PATH"
    exit 1
}

# Pull latest code from repository
echo "Pulling latest code..."
git pull origin main || {
    echo "ERROR: Git pull failed"
    exit 1
}

# Build and restart the specific service using docker-compose
echo "Building and restarting service: $TARGET_SERVICE_NAME..."
docker compose build "$TARGET_SERVICE_NAME" || {
    echo "ERROR: Docker compose build failed"
    exit 1
}

docker compose up -d "$TARGET_SERVICE_NAME" || {
    echo "ERROR: Docker compose up failed"
    exit 1
}

# Optional: Clean up dangling images
echo "Cleaning up unused Docker images..."
docker image prune -f

echo "====================================="
echo "Deployment completed successfully at $(date)"
echo "====================================="
