FROM almir/webhook:latest

USER root

# Install Docker CLI, docker-compose, and git
RUN apk --update --no-cache add \
    docker-cli \
    docker-cli-compose \
    git \
    bash \
    && rm -rf /var/cache/apk/*

# Run as non-root user (webhook already creates 'webhook' user)
USER webhook

WORKDIR /etc/webhook
