# GitHub Webhook for Continuous Deployment

A lightweight Docker-based webhook receiver that triggers continuous deployment from GitHub push events. Runs behind Traefik with automatic HTTPS and integrates with docker-compose for seamless service updates.

## Features

- **Secure GitHub Webhook Integration**: HMAC-SHA256 signature verification
- **Traefik Integration**: Automatic HTTPS with Let's Encrypt, rate limiting
- **Docker-based**: Runs in a container with minimal dependencies
- **Selective Deployment**: Rebuilds and restarts only the specified service
- **Branch Filtering**: Only triggers on configured branch (default: `main`)
- **Comprehensive Logging**: Detailed deployment logs with timestamps

## Architecture

```
GitHub Push → Webhook Endpoint (Traefik) → adnanh/webhook → deploy.sh
                                                                   ↓
                                                    git pull → docker compose build
                                                                   ↓
                                                    docker compose up -d → Service Restart
```

## Prerequisites

- Docker and Docker Compose installed
- Traefik running as reverse proxy
- Domain name pointing to your server
- GitHub repository with your application code
- Target application with docker-compose.yml

## Quick Start

### 1. Configuration

Clone this repository and create your environment file:

```bash
cp .env.example .env
```

Generate a webhook secret:

```bash
openssl rand -hex 32
```

Edit `.env` with your configuration:

```bash
# GitHub Webhook Secret
WEBHOOK_SECRET=<generated_secret>

# Traefik Configuration
WEBHOOK_DOMAIN=webhook.yourdomain.com
TRAEFIK_NETWORK=traefik
TRAEFIK_CERT_RESOLVER=letsencrypt

# Target Application Configuration
TARGET_REPO_PATH=/path/to/your/application
TARGET_SERVICE_NAME=your_service_name
```

### 2. Deploy the Webhook Service

Build and start the webhook container:

```bash
docker compose build
docker compose up -d
```

Check the logs:

```bash
docker compose logs -f webhook
```

### 3. Configure GitHub Webhook

1. Go to your GitHub repository
2. Navigate to **Settings** → **Webhooks** → **Add webhook**
3. Configure:
   - **Payload URL**: `https://webhook.yourdomain.com/hooks/deploy`
   - **Content type**: `application/json`
   - **Secret**: Use the same secret from your `.env` file
   - **SSL verification**: Enable
   - **Which events**: Select "Just the push event"
   - **Active**: Check
4. Click **Add webhook**

### 4. Test the Webhook

Push a commit to your main branch and monitor:

```bash
# Watch webhook logs
docker compose logs -f webhook

# Check target service status
docker compose -f /path/to/your/application/docker-compose.yml ps
```

You can also test webhook deliveries in GitHub:
- Go to **Settings** → **Webhooks** → Click on your webhook
- View **Recent Deliveries** for request/response details

## Project Structure

```
deployment-webhook/
├── Dockerfile                    # Custom webhook image with Docker CLI
├── docker-compose.yml           # Webhook service with Traefik labels
├── hooks/
│   └── hooks.json              # Webhook configuration
├── scripts/
│   └── deploy.sh               # Deployment script
├── .env.example                # Environment variables template
├── .gitignore                  # Git ignore rules
└── README.md                   # This file
```

## Configuration Details

### Branch Filtering

By default, the webhook only triggers on pushes to the `main` branch. To change this, edit `hooks/hooks.json`:

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

### Custom Deployment Script

The `scripts/deploy.sh` file contains the deployment logic. Customize it for your needs:

- Change the git branch in `git pull origin main`
- Add pre/post deployment hooks
- Implement rollback logic
- Add notifications (Slack, Discord, email)
- Run tests before deployment

### Rate Limiting

The default configuration allows 10 requests per second with a burst of 20. Adjust in `docker-compose.yml`:

```yaml
- "traefik.http.middlewares.webhook-ratelimit.ratelimit.average=10"
- "traefik.http.middlewares.webhook-ratelimit.ratelimit.burst=20"
```

## Security Best Practices

- **HMAC Verification**: All requests are validated with HMAC-SHA256 signatures
- **HTTPS Only**: Traefik enforces SSL/TLS encryption
- **Strong Secrets**: Use cryptographically secure random strings (32+ characters)
- **Branch Filtering**: Only configured branches trigger deployments
- **Rate Limiting**: Prevents abuse and DoS attacks
- **Read-Only Mounts**: Hooks and scripts are mounted read-only
- **Non-Root User**: Container runs as non-root webhook user
- **Minimal Permissions**: Only necessary Docker socket access

### Additional Security Measures

**IP Whitelisting** (optional): Restrict access to GitHub's webhook IPs via Traefik:

```yaml
- "traefik.http.middlewares.ipwhitelist.ipwhitelist.sourcerange=192.30.252.0/22,185.199.108.0/22,140.82.112.0/20,143.55.64.0/20"
- "traefik.http.routers.webhook.middlewares=webhook-ratelimit,ipwhitelist"
```

**Git Authentication**: For private repositories, configure SSH keys or deploy tokens in your target application directory.

## Troubleshooting

### Common Issues

**403 Forbidden**
- **Cause**: Signature mismatch
- **Solution**: Verify `WEBHOOK_SECRET` in `.env` matches GitHub webhook secret

**Deployment not triggering**
- **Cause**: Wrong branch filter
- **Solution**: Check `hooks/hooks.json` - ensure `refs/heads/main` matches your branch

**Git pull fails**
- **Cause**: Authentication issues
- **Solution**: Configure SSH keys or credentials in `TARGET_REPO_PATH`

**Docker permission denied**
- **Cause**: Docker socket not accessible
- **Solution**: Verify `/var/run/docker.sock` is mounted and webhook user has access

**Service not restarting**
- **Cause**: Wrong service name
- **Solution**: Check `TARGET_SERVICE_NAME` matches service in target docker-compose.yml

**Traefik not routing**
- **Cause**: Network or label misconfiguration
- **Solution**: Verify `TRAEFIK_NETWORK` exists and labels are correct

### Debugging

View detailed webhook logs:

```bash
docker compose logs -f webhook
```

Test deployment script manually:

```bash
docker compose exec webhook /scripts/deploy.sh "test-commit-id" "user/repo" "refs/heads/main"
```

Check GitHub webhook deliveries:
- Repository → Settings → Webhooks → Recent Deliveries
- Look for green checkmark (200 response)
- Review request/response details

## Advanced Usage

### Multiple Webhooks

To deploy multiple applications, create multiple hook configurations in `hooks/hooks.json`:

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

Add notification logic to `scripts/deploy.sh`:

```bash
# Example: Slack notification
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Deployment of '"$REPO_NAME"' completed"}' \
  YOUR_SLACK_WEBHOOK_URL
```

### Rollback Support

Implement rollback by tagging successful deployments:

```bash
# Tag current deployment
docker tag your-app:latest your-app:previous

# To rollback
docker tag your-app:previous your-app:latest
docker compose up -d your-service
```

## License

MIT

## Contributing

Contributions welcome! Please open an issue or submit a pull request.

## Support

For issues or questions:
- Check the Troubleshooting section
- Review GitHub webhook delivery logs
- Check container logs: `docker compose logs webhook`
