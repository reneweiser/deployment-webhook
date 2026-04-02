FROM almir/webhook:2.8.3

USER root

ARG DOCKER_GID=999

# Install Docker CLI, docker-compose, git, bash, and flock (util-linux)
RUN apk --update --no-cache add \
    docker-cli \
    docker-cli-compose \
    git \
    bash \
    util-linux \
    && rm -rf /var/cache/apk/*

# Create docker group with the host's Docker socket GID and add webhook user
# Remove any existing group that occupies the target GID (often 'ping' in Alpine)
RUN existing_group=$(getent group ${DOCKER_GID} | cut -d: -f1) && \
    [ -n "$existing_group" ] && delgroup "$existing_group" 2>/dev/null || true; \
    addgroup -g ${DOCKER_GID} docker && addgroup webhook docker

# Create deployment log directory
RUN mkdir -p /var/log/deployments && chown webhook:webhook /var/log/deployments

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD nc -w 1 localhost 9000 < /dev/null || exit 1

# Run as non-root user (webhook already creates 'webhook' user)
USER webhook

WORKDIR /etc/webhook
