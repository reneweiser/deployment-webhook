FROM almir/webhook:latest

USER root

# Install Docker CLI, docker-compose, and git
RUN apk --update --no-cache add \
    docker-cli \
    docker-cli-compose \
    git \
    bash \
    && rm -rf /var/cache/apk/*

# Add webhook user to GID 999 group (matching host docker group)
# The ping group already has GID 999, so we'll add webhook to it
RUN addgroup webhook ping

# Run as non-root user (webhook already creates 'webhook' user)
USER webhook

WORKDIR /etc/webhook
