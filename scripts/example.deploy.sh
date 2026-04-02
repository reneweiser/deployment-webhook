#!/bin/bash
set -euo pipefail

# Get arguments passed from webhook
COMMIT_ID="${1:-}"
REPO_NAME="${2:-}"
BRANCH_REF="${3:-}"
BRANCH_NAME="${BRANCH_REF#refs/heads/}"

# --- Concurrency lock (outer scope, before pipe) ---
command -v flock >/dev/null 2>&1 || { echo "ERROR: flock not found. Rebuild the webhook image with: docker compose build --no-cache webhook"; exit 1; }
LOCK_FILE="/var/log/deployments/deploy-${TARGET_SERVICE_NAME}.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "ERROR: Another deployment is already in progress for ${TARGET_SERVICE_NAME}. Skipping."
    exit 1
fi

# --- Log rotation (clean up logs older than 30 days) ---
find /var/log/deployments -name "deploy-*.log" -mtime +30 -delete 2>/dev/null || true

# --- Main deployment logic (wrapped for pipe-based logging) ---
main() {
    echo "====================================="
    echo "Deployment triggered at $(date)"
    echo "Repository: $REPO_NAME"
    echo "Branch: $BRANCH_NAME ($BRANCH_REF)"
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
    echo "Pulling latest code from branch '$BRANCH_NAME'..."
    git pull origin "$BRANCH_NAME" 200>&- || {
        echo "ERROR: Git pull failed"
        exit 1
    }

    # Build the specific service
    echo "Building service: $TARGET_SERVICE_NAME..."
    docker compose build "$TARGET_SERVICE_NAME" 200>&- || {
        echo "ERROR: Docker compose build failed"
        exit 1
    }

    # Restart the service (fail-loud with recovery info, no false-confidence rollback)
    echo "Restarting service: $TARGET_SERVICE_NAME..."
    docker compose up -d "$TARGET_SERVICE_NAME" 200>&- || {
        echo "CRITICAL: Deploy failed for $TARGET_SERVICE_NAME"
        echo "Previous commit: $(git rev-parse HEAD~1 2>/dev/null || echo 'unknown')"
        echo "To manually rollback: git checkout HEAD~1 && docker compose build $TARGET_SERVICE_NAME && docker compose up -d $TARGET_SERVICE_NAME"
        exit 1
    }

    # Clean up dangling images
    echo "Cleaning up unused Docker images..."
    docker image prune -f 200>&-

    echo "====================================="
    echo "Deployment completed successfully at $(date)"
    echo "====================================="
}

# --- Run main with persistent logging ---
LOG_FILE="/var/log/deployments/deploy-$(date +%Y%m%d-%H%M%S).log"
main 2>&1 | tee -a "$LOG_FILE"
exit ${PIPESTATUS[0]}
