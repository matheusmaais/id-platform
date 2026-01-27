# Backstage Custom Image with OIDC Support

This directory contains the custom Backstage image with OIDC authentication support for the Internal Developer Platform.

## Why Custom Image?

Backstage requires auth providers to be installed as Node.js dependencies. The official `ghcr.io/backstage/backstage:latest` image is a minimal example that does **not** include any auth providers.

To enable OIDC authentication with AWS Cognito, we must:
1. Add `@backstage/plugin-auth-backend-module-oidc-provider` to `package.json`
2. Build a custom image with this dependency
3. Use this image in our Helm deployment

This is the **standard practice** for all production Backstage deployments.

## Structure

```
backstage-custom/
├── Dockerfile                      # Multi-stage build (builder + runtime)
├── build-and-push.sh              # Automated build and push to ECR
├── package.json                   # Root workspace configuration
├── packages/
│   └── backend/
│       ├── package.json           # Backend dependencies (includes OIDC plugin)
│       ├── tsconfig.json          # TypeScript configuration
│       └── src/
│           └── index.ts           # Backend entry point with OIDC module
└── README.md                      # This file
```

## Security & Quality Features

### Multi-Stage Build
- **Builder stage**: Installs all dependencies and builds the application
- **Runtime stage**: Contains only production dependencies and built artifacts
- Result: Minimal attack surface, smaller image size

### Non-Root User
- Runs as user `backstage` (UID 1000)
- No root privileges in runtime
- Follows container security best practices

### Hardening
- Minimal base image: `node:20-bookworm-slim`
- Only essential runtime dependencies
- No build tools in final image
- Health check included

### Deterministic Builds
- Uses `yarn install --frozen-lockfile`
- Ensures reproducible builds
- No unexpected dependency updates

## Building the Image

### Prerequisites
- Docker installed and running
- AWS CLI configured with valid credentials
- Access to target AWS account

### Build and Push

```bash
cd backstage-custom

# Build and push with timestamp tag
./build-and-push.sh

# Build and push with custom tag
IMAGE_TAG=v1.0.0 ./build-and-push.sh
```

The script will:
1. ✓ Check prerequisites (docker, aws, jq)
2. ✓ Get AWS account information
3. ✓ Create ECR repository if needed
4. ✓ Login to ECR
5. ✓ Build multi-stage Docker image
6. ✓ Test image (startup and OIDC provider detection)
7. ✓ Push to ECR with versioned and latest tags
8. ✓ Display image information and next steps

### Manual Build (for testing)

```bash
# Build locally
docker build -t backstage-platform:test .

# Test locally
docker run -d \
  -e POSTGRES_HOST=localhost \
  -e POSTGRES_PORT=5432 \
  -e POSTGRES_USER=backstage \
  -e POSTGRES_PASSWORD=test \
  -e POSTGRES_DB=backstage \
  -p 7007:7007 \
  backstage-platform:test

# Check logs
docker logs <container-id>

# Verify OIDC provider is loaded
docker logs <container-id> 2>&1 | grep -i oidc
```

## Updating Helm Values

After building and pushing the image, update `platform-apps/backstage/values.yaml`:

```yaml
backstage:
  image:
    registry: <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
    repository: backstage-platform
    tag: <IMAGE_TAG>  # Use the timestamp tag from build output
```

Then commit and push:

```bash
git add platform-apps/backstage/values.yaml
git commit -m "feat(backstage): use custom image with OIDC support"
git push origin main
```

ArgoCD will automatically detect the change and deploy the new image.

## Dependencies

### Core Backstage
- `@backstage/backend-defaults` - Backend framework
- `@backstage/backend-plugin-auth` - Auth plugin system
- `@backstage/plugin-auth-backend` - Auth backend
- `@backstage/plugin-auth-node` - Auth utilities

### OIDC Provider (Critical)
- `@backstage/plugin-auth-backend-module-oidc-provider` - OIDC authentication

### Catalog & Plugins
- `@backstage/plugin-catalog-backend` - Software catalog
- `@backstage/plugin-scaffolder-backend` - Template scaffolding
- `@backstage/plugin-search-backend` - Search functionality
- `@backstage/plugin-techdocs-backend` - Documentation
- `@backstage/plugin-permission-backend` - RBAC

### Database
- `pg` - PostgreSQL client
- `better-sqlite3` - SQLite for local development

## Troubleshooting

### Build Fails with "Cannot find module"
- Ensure `yarn install` completed successfully
- Check `package.json` for correct dependency versions
- Try cleaning: `rm -rf node_modules && yarn install`

### Container Crashes on Startup
- Check logs: `docker logs <container-id>`
- Verify environment variables are set correctly
- Ensure PostgreSQL is accessible

### OIDC Provider Not Working
- Verify plugin is in `packages/backend/package.json`
- Check `src/index.ts` imports the OIDC module
- Review Backstage logs for auth provider registration

### ECR Push Fails
- Verify AWS credentials: `aws sts get-caller-identity`
- Check ECR permissions
- Ensure you're logged in: `aws ecr get-login-password | docker login ...`

## Image Tags

- **Timestamp tags** (e.g., `20260127-143022`): Immutable, recommended for production
- **`latest` tag**: Always points to most recent build, useful for development

## Maintenance

### Updating Dependencies

```bash
cd backstage-custom
yarn upgrade-interactive --latest
```

Review changes carefully, test locally, then rebuild and push.

### Security Scanning

ECR automatically scans images on push (configured with `scanOnPush=true`).

View scan results:
```bash
aws ecr describe-image-scan-findings \
  --repository-name backstage-platform \
  --image-id imageTag=<TAG> \
  --region us-east-1
```

## References

- [Backstage Documentation](https://backstage.io/docs/)
- [OIDC Auth Provider](https://backstage.io/docs/auth/oidc/provider)
- [Backstage Backend System](https://backstage.io/docs/backend-system/)
- [AWS ECR Documentation](https://docs.aws.amazon.com/ecr/)
