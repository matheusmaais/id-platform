# ECR Configuration Guide

This document explains how Amazon ECR (Elastic Container Registry) is configured in the platform and how CI/CD pipelines use it.

## Overview

The platform uses Amazon ECR to store Docker images for applications. ECR repositories are created **dynamically** by CI/CD pipelines on first use, eliminating the need to pre-create repositories via Terraform.

## Architecture

```
┌─────────────────┐       ┌──────────────┐       ┌─────────────┐
│  GitHub Actions │──────▶│  AWS ECR     │──────▶│  EKS Pods   │
│  (Build & Push) │ OIDC  │  (Registry)  │ Pull  │  (Runtime)  │
└─────────────────┘       └──────────────┘       └─────────────┘
```

## Terraform Resources

### 1. ECR Repositories (Optional Pre-creation)

Located in `cluster/terraform/ecr.tf`, this resource allows **optional** pre-creation of ECR repositories during platform bootstrap:

```hcl
resource "aws_ecr_repository" "platform_apps" {
  for_each = toset(try(local.config_file.ecr.repositories, []))

  name                 = each.value
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}
```

**Configuration in `config.yaml`:**

```yaml
ecr:
  # List of ECR repository names to pre-create
  # Leave empty [] for dynamic creation only (recommended for MVP)
  repositories: []
  # Example for pre-creating repositories:
  # repositories:
  #   - "sample-nodejs-app"
  #   - "platform-backend"
```

### 2. Lifecycle Policies

Automatic image cleanup to manage storage costs:

```hcl
resource "aws_ecr_lifecycle_policy" "platform_apps" {
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 production images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["prod-", "v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep last 5 staging images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["staging-", "dev-"]
          countType     = "imageCountMoreThan"
          countNumber   = 5
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 3
        description  = "Expire untagged images older than 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      }
    ]
  })
}
```

### 3. IAM Permissions

#### EKS Nodes (Pull Images)

```hcl
data "aws_iam_policy_document" "ecr_pull" {
  statement {
    actions = [
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy_attachment" "ecr_pull" {
  role       = module.eks.eks_managed_node_groups["default"].iam_role_name
  policy_arn = aws_iam_policy.ecr_pull.arn
}
```

#### GitHub Actions (Push Images via OIDC)

```hcl
resource "aws_iam_openid_connect_provider" "github" {
  count = try(local.config_file.github.enable_oidc, false) ? 1 : 0

  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

data "aws_iam_policy_document" "github_ecr_push" {
  statement {
    sid    = "ECRPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = ["arn:aws:ecr:${local.region}:${account_id}:repository/*"]
  }

  statement {
    sid    = "ECRCreateRepository"
    effect = "Allow"
    actions = [
      "ecr:CreateRepository",
      "ecr:DescribeRepositories",
      "ecr:PutLifecyclePolicy",
      "ecr:PutImageScanningConfiguration",
    ]
    resources = ["*"]
  }
}
```

## CI/CD Integration

### GitHub Actions Workflow

The Backstage scaffolder template generates a `.github/workflows/ci-cd.yaml` file that:

1. **Authenticates to AWS via OIDC** (no static credentials)
2. **Creates ECR repository** if it doesn't exist (dynamic provisioning)
3. **Builds and pushes Docker image** with multiple tags (`latest`, `<git-sha>`)
4. **Updates GitOps repository** with new image tag

**Key workflow steps:**

```yaml
- name: Configure AWS credentials (OIDC)
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
    aws-region: ${{ env.AWS_REGION }}

- name: Login to Amazon ECR
  uses: aws-actions/amazon-ecr-login@v2

- name: Ensure ECR repository exists (DEV MVP)
  run: |
    aws ecr describe-repositories --repository-names "${{ env.ECR_REPOSITORY }}" >/dev/null 2>&1 || \
    aws ecr create-repository \
      --repository-name "${{ env.ECR_REPOSITORY }}" \
      --image-scanning-configuration scanOnPush=true \
      --encryption-configuration encryptionType=AES256 >/dev/null

- name: Build and push image
  uses: docker/build-push-action@v5
  with:
    push: true
    tags: |
      ${{ env.ECR_REGISTRY }}/${{ env.ECR_REPOSITORY }}:${{ github.sha }}
      ${{ env.ECR_REGISTRY }}/${{ env.ECR_REPOSITORY }}:latest
```

### Required GitHub Secrets

Each application repository needs **ONE secret** to authenticate with AWS:

| Secret Name       | Description                                      | How to Get                              |
|-------------------|--------------------------------------------------|-----------------------------------------|
| `AWS_ROLE_ARN`    | IAM role ARN for GitHub Actions OIDC             | `terraform output github_ecr_push_role_arn` |

**Example value:**

```
arn:aws:iam::948881762705:role/idp-poc-darede-cluster-github-ecr-push
```

## Image Tagging Strategy

### Development/Staging

- **Tag format:** `<git-sha>` (e.g., `a1b2c3d`)
- **Latest tag:** `latest`
- **Retention:** Last 5 images per prefix (`dev-`, `staging-`)

### Production

- **Tag format:** `prod-<version>` (e.g., `prod-v1.0.0`) or semantic version `v1.0.0`
- **Retention:** Last 10 production images

### Example

```bash
# Development build
948881762705.dkr.ecr.us-east-1.amazonaws.com/hello-node:a1b2c3d
948881762705.dkr.ecr.us-east-1.amazonaws.com/hello-node:latest

# Production release
948881762705.dkr.ecr.us-east-1.amazonaws.com/hello-node:prod-v1.0.0
948881762705.dkr.ecr.us-east-1.amazonaws.com/hello-node:v1.0.0
```

## Configuration Reference

### Enable GitHub OIDC in `config.yaml`

```yaml
github:
  # Enable GitHub OIDC provider for CI/CD pipelines
  enable_oidc: true
  # GitHub organization that can assume the ECR push role
  org: "darede-labs"
```

### Optional: Pre-create ECR Repositories

```yaml
ecr:
  # List of ECR repository names to pre-create during bootstrap
  # Leave empty [] for dynamic creation (recommended)
  repositories:
    - "platform-backend"
    - "platform-frontend"
```

## Security Best Practices

1. **OIDC over static credentials:** GitHub Actions authenticate via OIDC, eliminating the need for long-lived AWS credentials
2. **Least privilege:** IAM role only allows ECR push/pull and repository creation
3. **Image scanning:** All images are scanned for vulnerabilities on push
4. **Encryption at rest:** Images are encrypted with AES256 (or KMS for production)
5. **Lifecycle policies:** Automatic cleanup prevents storage cost bloat
6. **Immutable tags:** Consider using immutable tags for production images

## Troubleshooting

### Issue: GitHub Actions cannot push to ECR

**Symptoms:**
```
Error: failed to push image: error creating push request: denied: User is not authorized
```

**Solution:**
1. Verify `AWS_ROLE_ARN` secret is set correctly in GitHub repository
2. Check that GitHub OIDC provider is enabled in `config.yaml`:
   ```yaml
   github:
     enable_oidc: true
   ```
3. Re-run Terraform to create the OIDC provider:
   ```bash
   cd cluster/terraform
   terraform apply -target=aws_iam_openid_connect_provider.github
   ```
4. Verify the IAM role trust policy allows your GitHub org:
   ```bash
   terraform output github_ecr_push_role_arn
   aws iam get-role --role-name idp-poc-darede-cluster-github-ecr-push --query 'Role.AssumeRolePolicyDocument'
   ```

### Issue: EKS pods cannot pull images from ECR

**Symptoms:**
```
Failed to pull image "948881762705.dkr.ecr.us-east-1.amazonaws.com/app:latest": rpc error: code = Unknown desc = Error response from daemon: pull access denied
```

**Solution:**
1. Verify ECR pull policy is attached to EKS node role:
   ```bash
   terraform output -json | jq '.cluster_name.value'
   aws iam list-attached-role-policies --role-name <node-role-name>
   ```
2. Check that the ECR repository exists:
   ```bash
   aws ecr describe-repositories --repository-names <app-name>
   ```

### Issue: Lifecycle policy deleted production images

**Symptoms:** Production deployment fails because image was deleted by lifecycle policy

**Solution:**
1. Ensure production images use proper tag prefixes (`prod-`, `v`)
2. Adjust lifecycle policy retention count in `cluster/terraform/ecr.tf` if needed
3. Re-tag critical images that were deleted:
   ```bash
   docker pull <old-tag>
   docker tag <old-tag> <new-tag-with-prod-prefix>
   docker push <new-tag-with-prod-prefix>
   ```

## Terraform Outputs

| Output Name                 | Description                                    |
|-----------------------------|------------------------------------------------|
| `ecr_repository_urls`       | Map of ECR repository URLs                     |
| `ecr_repository_arns`       | Map of ECR repository ARNs                     |
| `ecr_account_url`           | Base ECR URL for the AWS account               |
| `github_oidc_provider_arn`  | ARN of GitHub OIDC provider                    |
| `github_ecr_push_role_arn`  | ARN of IAM role for GitHub Actions             |

**Example:**

```bash
terraform output ecr_account_url
# 948881762705.dkr.ecr.us-east-1.amazonaws.com

terraform output github_ecr_push_role_arn
# arn:aws:iam::948881762705:role/idp-poc-darede-cluster-github-ecr-push
```

## Cost Optimization

1. **Lifecycle policies:** Automatically delete old images to reduce storage costs
2. **Compression:** Use multi-stage Docker builds to minimize image size
3. **Scanning:** Enable image scanning to catch vulnerabilities early (avoid production issues)
4. **Encryption:** Use AES256 (free) instead of KMS for dev/staging environments

## Next Steps

- [CI/CD GitHub Actions Documentation](./CI-CD-GITHUB-ACTIONS.md) *(to be created)*
- [Backstage Scaffolder Templates](../templates/backstage/README.md) *(to be created)*
- [Platform Features Overview](./PLATFORM-FEATURES.md)
