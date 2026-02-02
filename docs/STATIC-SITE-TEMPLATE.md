# Static Website + CDN Template

This document describes the Static Website template that provisions S3 + CloudFront infrastructure via Crossplane.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              User Flow                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. Backstage          2. GitHub              3. ArgoCD                     │
│  ┌──────────┐         ┌──────────┐          ┌──────────┐                   │
│  │ Create   │────────▶│ idp-*    │─────────▶│ Detect   │                   │
│  │ Template │         │ repo     │          │ & Apply  │                   │
│  └──────────┘         └──────────┘          └──────────┘                   │
│                             │                     │                         │
│                             │                     ▼                         │
│                             │              4. Crossplane                    │
│                             │              ┌──────────┐                     │
│                             │              │ Create   │                     │
│                             │              │ AWS Infra│                     │
│                             │              └──────────┘                     │
│                             │                     │                         │
│                             ▼                     ▼                         │
│                       5. GitHub CI         ┌─────────────┐                  │
│                       ┌──────────┐         │    AWS      │                  │
│                       │ Publish  │────────▶│ S3 + CF    │                  │
│                       │ to S3    │         └─────────────┘                  │
│                       └──────────┘               │                          │
│                                                  ▼                          │
│                                            ┌──────────┐                     │
│                                            │  Users   │                     │
│                                            └──────────┘                     │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Components

### Crossplane Resources

The template creates the following AWS resources via Crossplane:

| Resource | Name Pattern | Description |
|----------|--------------|-------------|
| S3 Bucket | `{siteName}-static-{env}` | Private bucket for static files |
| Public Access Block | `{siteName}-static-{env}-pab` | Blocks all public access |
| Origin Access Control | `{siteName}-static-oac` | Secure CloudFront access |
| CloudFront Distribution | `{siteName}-static-cf` | CDN with edge caching |
| Bucket Policy | `{siteName}-static-{env}-policy` | Allows CloudFront OAC |

### Files Generated

```
idp-{siteName}/
├── site/
│   ├── index.html              # Hello world page
│   └── error.html              # 404 page
├── deploy/
│   ├── namespace.yaml          # K8s namespace
│   └── static-website-claim.yaml   # Crossplane claim
├── .github/workflows/
│   └── publish.yaml            # CI pipeline
├── catalog-info.yaml           # Backstage component
├── README.md                   # Documentation
└── .gitignore
```

## Prerequisites

### 1. Crossplane Installed

The platform must have Crossplane installed with AWS providers:

```bash
# Verify Crossplane is running
kubectl get pods -n crossplane-system

# Verify providers are healthy
kubectl get providers.pkg.crossplane.io

# Verify XRD exists
kubectl get xrd xstaticwebsites.platform.darede.io
```

### 2. GitHub Actions IAM Role

The GitHub Actions workflow uses OIDC to assume an IAM role. This role needs additional permissions for static sites.

#### Required Permissions

Add these permissions to your GitHub Actions IAM role (`github-actions-ecr-push` or your custom name):

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "S3StaticSiteAccess",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:ListBucket",
                "s3:HeadBucket"
            ],
            "Resource": [
                "arn:aws:s3:::*-static-dev",
                "arn:aws:s3:::*-static-dev/*",
                "arn:aws:s3:::*-static-staging",
                "arn:aws:s3:::*-static-staging/*",
                "arn:aws:s3:::*-static-prod",
                "arn:aws:s3:::*-static-prod/*"
            ]
        },
        {
            "Sid": "CloudFrontInvalidation",
            "Effect": "Allow",
            "Action": [
                "cloudfront:CreateInvalidation",
                "cloudfront:GetInvalidation",
                "cloudfront:ListInvalidations",
                "cloudfront:GetDistribution",
                "cloudfront:ListDistributions"
            ],
            "Resource": "*"
        }
    ]
}
```

#### Terraform Example

If you manage the role via Terraform, add this policy:

```hcl
# Add to your GitHub Actions role's policies
resource "aws_iam_policy" "github_actions_static_sites" {
  name        = "github-actions-static-sites"
  description = "Permissions for GitHub Actions to deploy static sites"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3StaticSiteAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:HeadBucket"
        ]
        Resource = [
          "arn:aws:s3:::*-static-*",
          "arn:aws:s3:::*-static-*/*"
        ]
      },
      {
        Sid    = "CloudFrontInvalidation"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateInvalidation",
          "cloudfront:GetInvalidation",
          "cloudfront:ListInvalidations",
          "cloudfront:GetDistribution",
          "cloudfront:ListDistributions"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_static_sites" {
  role       = "github-actions-ecr-push"  # Your role name
  policy_arn = aws_iam_policy.github_actions_static_sites.arn
}
```

## Usage

### Creating a Static Site

1. Go to Backstage: `https://backstage.<domain>/create`
2. Select "Create Static Website + CDN"
3. Fill in:
   - **Site Name**: Lowercase, alphanumeric with dashes (e.g., `my-docs`)
   - **Description**: Brief description
   - **Owner**: Team or user
   - **Price Class**: CloudFront distribution (affects cost)
4. Click "Create"

### What Happens Next

1. **GitHub**: Repository `idp-{siteName}` is created
2. **ArgoCD**: Detects the repo and applies the Crossplane claim
3. **Crossplane**: Provisions S3 bucket and CloudFront distribution
4. **GitHub Actions**: First push triggers site deployment
5. **CloudFront**: Site is available at the CloudFront URL

### Getting the Site URL

After provisioning (may take 5-10 minutes for CloudFront):

```bash
# From Crossplane claim status
kubectl get staticwebsite {siteName} -n {siteName} \
  -o jsonpath='{.status.cloudfrontUrl}'

# Or via AWS CLI
aws cloudfront list-distributions \
  --query "DistributionList.Items[?Origins.Items[?contains(DomainName, '{siteName}-static')]].DomainName" \
  --output text
```

## Troubleshooting

### Crossplane Claim Not Ready

```bash
# Check claim status
kubectl describe staticwebsite {siteName} -n {siteName}

# Check composition status
kubectl get bucket,cloudfrontdistribution -n {siteName}

# Check Crossplane logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/provider=provider-aws-s3 --tail=50
```

### CI Pipeline Failing

Common issues:

1. **Bucket not found**: Crossplane may still be provisioning. The CI waits up to 5 minutes.
2. **Access denied**: GitHub Actions role missing S3/CloudFront permissions.
3. **OIDC error**: Verify the trust policy includes your GitHub org/repo.

```bash
# Check bucket exists
aws s3 ls | grep {siteName}-static

# Test role assumption (from GitHub Actions)
# Check the workflow logs for STS errors
```

### CloudFront 403 Errors

The bucket policy may not be applied yet:

```bash
# Check bucket policy
aws s3api get-bucket-policy --bucket {siteName}-static-dev

# Verify OAC
aws cloudfront list-origin-access-controls
```

## Cost Considerations

| Component | Cost |
|-----------|------|
| S3 Storage | ~$0.023/GB/month |
| S3 Requests | ~$0.0004/1000 GET |
| CloudFront Data Transfer | ~$0.085/GB (first 10TB) |
| CloudFront Requests | ~$0.0075/10000 HTTPS |
| CloudFront Invalidations | First 1000/month free |

**Estimated monthly cost for a typical static site**: $1-5/month

### Price Classes

| Class | Coverage | Cost |
|-------|----------|------|
| `PriceClass_100` | NA, EU | Lowest |
| `PriceClass_200` | + Asia, Africa, Middle East | Medium |
| `PriceClass_All` | All edge locations | Highest |

## Related Documentation

- [Crossplane AWS Provider](https://marketplace.upbound.io/providers/upbound/provider-aws)
- [CloudFront Origin Access Control](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
