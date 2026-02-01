# ${{ values.name }}

${{ values.description }}

## Architecture

This static website is hosted on AWS with the following components:

- **S3 Bucket**: `idp-${{ values.name }}-static` - Stores the website files
- **CloudFront**: CDN distribution with global edge locations
- **Origin Access Control**: Secures S3 access (bucket is private)

```
┌──────────────────┐     ┌──────────────┐     ┌────────────┐
│   CloudFront     │────▶│     OAC      │────▶│  S3 Bucket │
│   (CDN Edge)     │     │              │     │            │
└──────────────────┘     └──────────────┘     └────────────┘
         ▲
         │ HTTPS
         │
    ┌────┴────┐
    │  Users  │
    └─────────┘
```

## Quick Start

### Making Changes

1. Edit files in the `site/` directory
2. Commit and push to `main` branch
3. GitHub Actions will automatically deploy

```bash
# Edit your site
vim site/index.html

# Deploy
git add .
git commit -m "Update site content"
git push origin main
```

### Local Development

Simply open `site/index.html` in your browser:

```bash
open site/index.html
```

Or use a local server:

```bash
npx serve site
```

## Directory Structure

```
.
├── site/                    # Website files (deployed to S3)
│   ├── index.html          # Main page
│   └── error.html          # 404 error page
├── deploy/                  # Kubernetes/Crossplane manifests
│   ├── namespace.yaml      # Namespace for claim
│   └── static-website-claim.yaml  # Crossplane claim
├── .github/
│   └── workflows/
│       └── publish.yaml    # CI/CD pipeline
├── catalog-info.yaml       # Backstage component definition
└── README.md               # This file
```

## Infrastructure

The infrastructure is managed by Crossplane. To check status:

```bash
# View claim status
kubectl get staticwebsite ${{ values.name }} -n ${{ values.name }} -o yaml

# Check underlying resources
kubectl get bucket,cloudfrontdistribution -n ${{ values.name }}
```

### Getting the Site URL

The CloudFront URL is available in the claim status:

```bash
kubectl get staticwebsite ${{ values.name }} -n ${{ values.name }} \
  -o jsonpath='{.status.cloudfrontUrl}'
```

## CI/CD Pipeline

The GitHub Actions workflow (`.github/workflows/publish.yaml`) handles:

1. **Authentication**: Uses OIDC to assume AWS role (no static credentials)
2. **Wait**: Waits for S3 bucket to be provisioned by Crossplane
3. **Sync**: Uploads `site/` directory to S3 with proper cache headers
4. **Invalidate**: Creates CloudFront invalidation to clear cache

### Manual Deployment

You can trigger a deployment manually:

```bash
gh workflow run publish.yaml
```

## Troubleshooting

### Site not updating?

CloudFront caches content. Wait for invalidation to complete or check:

```bash
# List recent invalidations
aws cloudfront list-invalidations \
  --distribution-id <DIST_ID> \
  --max-items 5
```

### Bucket not found?

The Crossplane claim may still be provisioning. Check status:

```bash
kubectl describe staticwebsite ${{ values.name }} -n ${{ values.name }}
```

### 403 Forbidden errors?

The bucket policy might not be applied yet. Verify OAC configuration:

```bash
aws s3api get-bucket-policy --bucket idp-${{ values.name }}-static
```

## Links

- [Repository](https://github.com/${{ values.githubOrg }}/${{ values.repoPrefix }}${{ values.name }})
- [CI Pipeline](https://github.com/${{ values.githubOrg }}/${{ values.repoPrefix }}${{ values.name }}/actions)
- [ArgoCD Application](https://argocd.${{ values.domain }}/applications/${{ values.repoPrefix }}${{ values.name }})
- [Backstage Catalog](https://backstage.${{ values.domain }}/catalog/default/component/${{ values.name }})
