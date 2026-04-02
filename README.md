# GitHub Webhook for Continuous Deployment

A lightweight Docker-based webhook receiver that triggers continuous deployment from GitHub push events. Supports both **Traefik** and **Caddy** as reverse proxies with automatic HTTPS.

## Features

- **Secure GitHub Webhook Integration**: HMAC-SHA256 signature verification
- **Reverse Proxy Support**: Works with Traefik or Caddy (via docker-compose overrides)
- **Docker-based**: Runs in a container with minimal dependencies
- **Selective Deployment**: Rebuilds and restarts only the specified service
- **Branch Filtering**: Only triggers on configured branch (default: `main`)
- **Concurrency Protection**: File-based locking prevents parallel deployments
- **Persistent Logging**: Timestamped deployment logs with automatic 30-day rotation
- **Fail-Loud Errors**: Clear error messages with manual rollback instructions on failure

## Architecture

```
GitHub Push --> Webhook Endpoint (Reverse Proxy) --> adnanh/webhook --> deploy.sh
                                                                          |
                                                           git pull --> docker compose build
                                                                          |
                                                           docker compose up -d --> Service Restart
```

## Prerequisites

- Docker and Docker Compose installed
- A reverse proxy running (Traefik or Caddy)
- Domain name pointing to your server
- GitHub repository with your application code
- Target application with docker-compose.yml at the repository root
- For private repos: SSH keys or git credentials configured in `TARGET_REPO_PATH`

## Quick Start

### 1. Configuration

Clone this repository and create your configuration files from the examples:

```bash
# Create environment file
cp .env.example .env

# Create hooks configuration
cp hooks/example.hooks.json hooks/hooks.json

# Create deployment script
cp scripts/example.deploy.sh scripts/deploy.sh
chmod +x scripts/deploy.sh
```

Generate a webhook secret:

```bash
openssl rand -hex 32
```

Edit `.env` with your configuration (see [Environment Variables](#environment-variables) below).

> **Important**: The `$WEBHOOK_SECRET` reference in `hooks.json` uses adnanh/webhook's built-in environment variable interpolation. Leave it as `$WEBHOOK_SECRET` -- do NOT replace it with the actual secret value. The secret is read from the environment at runtime.

### 2. Choose Your Reverse Proxy

Set the `COMPOSE_FILE` variable in `.env` based on your reverse proxy:

**Traefik:**
```bash
COMPOSE_FILE=docker-compose.yml:docker-compose.traefik.yml
```

**Caddy** (using [caddy-docker-proxy](https://github.com/lucaslorentz/caddy-docker-proxy)):
```bash
COMPOSE_FILE=docker-compose.yml:docker-compose.caddy.yml
```

**Local development** (no reverse proxy, direct port access):
```bash
COMPOSE_FILE=docker-compose.yml:docker-compose.local.yml
```

### 3. Deploy the Webhook Service

```bash
docker compose build
docker compose up -d
```

Check the logs:

```bash
docker compose logs -f webhook
```

### 4. Configure GitHub Webhook

1. Go to your GitHub repository
2. Navigate to **Settings** > **Webhooks** > **Add webhook**
3. Configure:
   - **Payload URL**: `https://webhook.yourdomain.com/hooks/deploy`
   - **Content type**: `application/json`
   - **Secret**: Use the same secret from your `.env` file
   - **SSL verification**: Enable
   - **Which events**: Select "Just the push event"
   - **Active**: Check
4. Click **Add webhook**

### 5. Test the Webhook

Push a commit to your target branch and monitor:

```bash
# Watch webhook logs
docker compose logs -f webhook

# Check deployment logs
docker compose exec webhook ls /var/log/deployments/

# Check target service status
docker compose -f /path/to/your/application/docker-compose.yml ps
```

You can also check webhook deliveries in GitHub:
- Go to **Settings** > **Webhooks** > Click on your webhook > **Recent Deliveries**

## Project Structure

```
deployment-webhook/
├── .dockerignore                     # Build context exclusions
├── .env.example                      # Environment variables template
├── .gitignore                        # Git ignore rules
├── Dockerfile                        # Webhook image with Docker CLI
├── README.md                         # This file
├── docker-compose.yml                # Base service (proxy-agnostic)
├── docker-compose.traefik.yml        # Traefik override (labels + network)
├── docker-compose.caddy.yml          # Caddy override (labels + network)
├── docker-compose.local.yml          # Local dev override (port mapping)
├── hooks/
│   ├── example.hooks.json            # Webhook config template (copy to hooks.json)
│   └── hooks.json                    # Your webhook config (gitignored)
└── scripts/
    ├── example.deploy.sh             # Deploy script template (copy to deploy.sh)
    └── deploy.sh                     # Your deploy script (gitignored)
```

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `COMPOSE_FILE` | Yes | - | Compose files to use (see [Choose Your Reverse Proxy](#2-choose-your-reverse-proxy)) |
| `WEBHOOK_SECRET` | Yes | - | GitHub webhook HMAC secret |
| `WEBHOOK_DOMAIN` | Yes | - | Domain for the webhook endpoint |
| `TARGET_REPO_PATH` | Yes | - | Absolute path to target application (same on host and in container) |
| `TARGET_SERVICE_NAME` | Yes | - | Docker Compose service name to rebuild |
| `TRAEFIK_NETWORK` | Traefik | `traefik-public` | External Docker network for Traefik |
| `TRAEFIK_CERT_RESOLVER` | Traefik | `letsencrypt` | Traefik certificate resolver name |
| `CADDY_NETWORK` | Caddy | `caddy` | External Docker network for Caddy |
| `DOCKER_GID` | No | `999` | GID of the Docker socket on the host |

### Detecting Docker GID

If the default GID (999) doesn't match your host:

```bash
# Linux
stat -c '%g' /var/run/docker.sock

# macOS
stat -f '%g' /var/run/docker.sock
```

Set `DOCKER_GID` in your `.env` and rebuild: `docker compose build --no-cache`

## Configuration Details

### Branch Filtering

The webhook only triggers on pushes to the branch configured in `hooks/hooks.json`. By default this is `main`. To change it, edit your `hooks/hooks.json`:

```json
{
  "match": {
    "type": "value",
    "value": "refs/heads/your-branch",
    "parameter": {
      "source": "payload",
      "name": "ref"
    }
  }
}
```

> **Note**: The branch filter in `hooks.json` does NOT support environment variable interpolation -- you must edit the value manually. The deploy script automatically pulls the correct branch from the webhook payload, so no script changes are needed.

### Rate Limiting (Traefik)

The default Traefik configuration allows 10 requests per second with a burst of 20. Adjust in `docker-compose.traefik.yml`:

```yaml
- "traefik.http.middlewares.webhook-ratelimit.ratelimit.average=10"
- "traefik.http.middlewares.webhook-ratelimit.ratelimit.burst=20"
```

### Deployment Logs

Deployment logs are stored in a persistent Docker volume (`deploy-logs`) at `/var/log/deployments/`. Logs older than 30 days are automatically cleaned up.

View recent deployment logs:

```bash
docker compose exec webhook ls -la /var/log/deployments/
docker compose exec webhook cat /var/log/deployments/deploy-YYYYMMDD-HHMMSS.log
```

## Security Best Practices

- **HMAC Verification**: All requests are validated with HMAC-SHA256 signatures
- **HTTPS Only**: Reverse proxy enforces SSL/TLS encryption
- **Strong Secrets**: Use cryptographically secure random strings (32+ characters)
- **Branch Filtering**: Only configured branches trigger deployments
- **Rate Limiting**: Prevents abuse (Traefik: built-in middleware)
- **Read-Only Mounts**: Hooks and scripts are mounted read-only
- **Non-Root User**: Container runs as non-root webhook user
- **Concurrency Lock**: File-based locking prevents parallel deployment races
- **No Port Exposure**: Base compose file exposes no ports -- webhook is only reachable through the reverse proxy

### IP Whitelisting (Traefik)

Restrict access to GitHub's webhook IPs:

```yaml
# Add to docker-compose.traefik.yml labels
- "traefik.http.middlewares.webhook-ipwhitelist.ipwhitelist.sourcerange=192.30.252.0/22,185.199.108.0/22,140.82.112.0/20,143.55.64.0/20"
- "traefik.http.routers.webhook.middlewares=webhook-ratelimit,webhook-ipwhitelist"
```

## Troubleshooting

### Deployments Not Triggering

**Cause**: Configuration files not created or secret mismatch.

**Check**:
1. Ensure `hooks/hooks.json` and `scripts/deploy.sh` exist (created from examples)
2. Verify `WEBHOOK_SECRET` in `.env` matches the secret in your GitHub webhook settings
3. Check webhook deliveries in GitHub: **Settings** > **Webhooks** > **Recent Deliveries**

> **Gotcha**: When `WEBHOOK_SECRET` is wrong, adnanh/webhook returns HTTP 200 with an empty body -- not 401 or 403. You will see no errors in any logs. If deployments silently stop, check the secret first.

### Deployment Fails but GitHub Shows Success

**Cause**: adnanh/webhook returns its `response-message` immediately when the webhook triggers, before the deploy script finishes. GitHub always sees "200 OK" regardless of whether the deployment succeeds or fails.

**Solution**: Monitor deployment logs for the actual outcome:

```bash
docker compose exec webhook cat /var/log/deployments/deploy-*.log | tail -50
```

Consider adding external alerting (Slack, email) to your `deploy.sh` for production use.

### Docker Permission Denied

**Cause**: Docker socket GID mismatch.

**Solution**: Check your host's Docker socket GID and set `DOCKER_GID` in `.env`:

```bash
stat -c '%g' /var/run/docker.sock
# Set DOCKER_GID to the output value, then rebuild:
docker compose build --no-cache
```

### Git Pull Fails

**Cause**: Authentication issues with private repositories.

**Solution**: The container has git but no SSH keys or credential helper. For private repos, configure authentication in your target application directory before setting up the webhook. Options:
- SSH keys: mount `~/.ssh` into the container
- HTTPS credentials: configure a git credential helper in `TARGET_REPO_PATH`
- Deploy tokens: set up a read-only deploy token in the target repo

### Service Not Restarting

**Cause**: Wrong service name or compose file not found.

**Solution**: Verify `TARGET_SERVICE_NAME` matches a service in the target application's docker-compose.yml. The target repo must have a `docker-compose.yml` at its root.

### Traefik Not Routing

**Cause**: Network or label misconfiguration.

**Solution**: Verify `TRAEFIK_NETWORK` matches your Traefik instance's network name and that the network exists (`docker network ls`).

### Caddy Not Routing

**Cause**: Network mismatch or caddy-docker-proxy not running.

**Solution**: Verify `CADDY_NETWORK` matches the network used by your caddy-docker-proxy instance. Check that the caddy-docker-proxy container is running and can see this container's labels.

### Concurrent Deployment Skipped

**Cause**: A deployment is already in progress.

**Solution**: This is expected behavior. The flock-based lock prevents parallel deployments. The skipped webhook will not deploy, but the next push will trigger a fresh deployment with the latest code.

## Advanced Usage

### Multiple Webhooks

Deploy multiple applications by creating multiple hook configurations in `hooks/hooks.json`:

```json
[
  {
    "id": "deploy-app1",
    "execute-command": "/scripts/deploy-app1.sh",
    ...
  },
  {
    "id": "deploy-app2",
    "execute-command": "/scripts/deploy-app2.sh",
    ...
  }
]
```

Configure different GitHub webhooks with URLs:
- `https://webhook.yourdomain.com/hooks/deploy-app1`
- `https://webhook.yourdomain.com/hooks/deploy-app2`

### Deployment Notifications

Add notification logic to your `scripts/deploy.sh`:

```bash
# Slack notification on success
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Deployment of '"$REPO_NAME"' completed ('"$COMMIT_ID"')"}' \
  YOUR_SLACK_WEBHOOK_URL

# Slack notification on failure (add to the CRITICAL error block)
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"FAILED: Deployment of '"$REPO_NAME"' failed!"}' \
  YOUR_SLACK_WEBHOOK_URL
```

### Manual Rollback

If a deployment fails, rollback manually:

```bash
cd /path/to/your/application
git checkout HEAD~1
docker compose build your_service
docker compose up -d your_service
```

## Migration from v1 (Single docker-compose.yml)

> **Warning**: If you are upgrading from the previous version (single `docker-compose.yml` with Traefik labels), you **must** add `COMPOSE_FILE` to your `.env` before running `docker compose up`. Without it, the webhook starts with no reverse proxy, no TLS, and no network -- a silent security regression.

Add this line to your `.env`:

```bash
COMPOSE_FILE=docker-compose.yml:docker-compose.traefik.yml
```

Also update `TRAEFIK_NETWORK=traefik-public` in your `.env` if you were using the previous default.

## License

MIT
