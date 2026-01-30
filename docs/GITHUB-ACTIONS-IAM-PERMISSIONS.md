# GitHub Actions IAM Role Permissions

## Overview

The GitHub Actions OIDC role (`github-actions-ecr-push`) is used by all application templates for AWS authentication.

**Current Configuration:**
- Role Name: `github-actions-ecr-push`
- OIDC Provider: `token.actions.githubusercontent.com`
- Allowed Repos: `repo:darede-labs/*:*`
- Description: GitHub Actions OIDC role for ECR push operations

## Required Permissions by Template

### 1. Node.js Application Template (idp-nodejs-app)

**Services:** ECR (Elastic Container Registry)

**Operations:**
- `ecr:GetAuthorizationToken` - Login to ECR
- `ecr:DescribeRepositories` - Check if repository exists
- `ecr:CreateRepository` - Create ECR repo if needed
- `ecr:PutImage` - Push Docker image
- `ecr:BatchCheckLayerAvailability` - Optimize layer uploads
- `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload` - Upload image layers

**Current Status:** ✅ Implemented (inline policy `ECRPushAccess`)

### 2. Static Website Template (idp-static-site) ⚠️ REQUIRES ADDITIONAL PERMISSIONS

**Services:** S3, CloudFront

**Required Operations:**

**S3 Permissions:**
- `s3:ListBucket` - Verify bucket exists before sync
- `s3:GetObject` - Read objects (for sync comparison)
- `s3:PutObject` - Upload site files
- `s3:DeleteObject` - Remove old files during sync
- `s3:PutObjectAcl` - Set object permissions

**CloudFront Permissions:**
- `cloudfront:ListDistributions` - Find distribution by origin
- `cloudfront:GetDistribution` - Get distribution details
- `cloudfront:CreateInvalidation` - Invalidate cache after upload

**Scope:** Resources must be limited to buckets/distributions created by Crossplane (follows naming convention `*-static-*`)

**Current Status:** ❌ NOT IMPLEMENTED - Needs additional inline policy

## Implementation

### Option 1: Add New Inline Policy (Recommended)

Add a second inline policy to the existing role without modifying `ECRPushAccess`.

**Policy Name:** `StaticSitePublish`

**Policy Document:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3StaticSiteBucketAccess",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:PutObjectAcl"
      ],
      "Resource": [
        "arn:aws:s3:::*-static-*",
        "arn:aws:s3:::*-static-*/*"
      ],
      "Condition": {
        "StringEquals": {
          "aws:ResourceAccount": "948881762705"
        }
      }
    },
    {
      "Sid": "CloudFrontStaticSiteAccess",
      "Effect": "Allow",
      "Action": [
        "cloudfront:ListDistributions",
        "cloudfront:GetDistribution",
        "cloudfront:CreateInvalidation"
      ],
      "Resource": "*"
    }
  ]
}
```

**Apply via AWS CLI:**

```bash
# Export policy to file
cat > /tmp/static-site-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3StaticSiteBucketAccess",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:PutObjectAcl"
      ],
      "Resource": [
        "arn:aws:s3:::*-static-*",
        "arn:aws:s3:::*-static-*/*"
      ],
      "Condition": {
        "StringEquals": {
          "aws:ResourceAccount": "948881762705"
        }
      }
    },
    {
      "Sid": "CloudFrontStaticSiteAccess",
      "Effect": "Allow",
      "Action": [
        "cloudfront:ListDistributions",
        "cloudfront:GetDistribution",
        "cloudfront:CreateInvalidation"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Apply policy to role
aws iam put-role-policy \
  --role-name github-actions-ecr-push \
  --policy-name StaticSitePublish \
  --policy-document file:///tmp/static-site-policy.json

# Verify
aws iam get-role-policy \
  --role-name github-actions-ecr-push \
  --policy-name StaticSitePublish
```

### Option 2: Use Managed Policy

Alternatively, attach AWS-managed policies (less secure, broader permissions):

```bash
aws iam attach-role-policy \
  --role-name github-actions-ecr-push \
  --policy-arn arn:aws:iam::aws:policy/CloudFrontFullAccess

aws iam attach-role-policy \
  --role-name github-actions-ecr-push \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
```

⚠️ **Not recommended:** Grants excessive permissions beyond static sites.

### Option 3: Create Separate Role (Alternative Architecture)

Create a dedicated role for static sites:

```bash
# Would require:
# 1. New OIDC trust policy
# 2. Dedicated S3+CloudFront policy
# 3. Update config/platform-params.yaml
# 4. Update Backstage environment parameters
# 5. Separate variable in template.yaml
```

❌ **Not recommended:** Increases complexity, requires template changes.

## Security Best Practices

1. **Least Privilege:** Current policy uses wildcard `*-static-*` to limit S3 access to Crossplane-managed buckets only
2. **Account Boundary:** S3 policy includes condition to restrict to account `948881762705`
3. **CloudFront Scope:** ListDistributions requires `*` resource, but operations are read-only except CreateInvalidation (limited blast radius)
4. **OIDC Trust:** Already configured to limit to `darede-labs/*` organization repos
5. **Audit:** Monitor CloudTrail for unexpected API calls from this role

## Verification

After applying the policy, test with a sample static site:

```bash
# 1. Create test site via Backstage
# 2. Wait for Crossplane to provision S3 + CloudFront
# 3. Commit change to site/index.html
# 4. GitHub Actions should:
#    - ✅ Sync to S3 successfully
#    - ✅ Invalidate CloudFront cache
#    - ✅ Print site URL
```

**Expected GitHub Actions Output:**

```
Waiting for bucket my-test-site-static-dev to be available...
Bucket my-test-site-static-dev is ready!
Syncing site/ to s3://my-test-site-static-dev...
Sync complete!
Found distribution: E1234ABCD5678
Creating CloudFront invalidation...
Invalidation created: I1234567890ABC
----------------------------------------
Site published successfully!
URL: https://d1234abcd5678.cloudfront.net
----------------------------------------
```

## Troubleshooting

### Error: "Access Denied" on S3 Sync

**Symptoms:**
```
An error occurred (AccessDenied) when calling the PutObject operation: Access Denied
```

**Solution:**
1. Verify policy is attached: `aws iam list-role-policies --role-name github-actions-ecr-push`
2. Check bucket naming matches pattern: `*-static-*`
3. Verify bucket exists: `aws s3 ls s3://YOUR-BUCKET-NAME`

### Error: "Access Denied" on CloudFront Invalidation

**Symptoms:**
```
An error occurred (AccessDenied) when calling the CreateInvalidation operation
```

**Solution:**
1. Verify CloudFront policy includes `CreateInvalidation`
2. Check distribution exists: `aws cloudfront list-distributions`
3. Verify role trust policy allows repo: `aws iam get-role --role-name github-actions-ecr-push`

### Workflow Skips CloudFront Step

**Symptoms:**
```
CloudFront distribution not found yet (may still be provisioning)
```

**Solution:**
- Expected behavior if distribution is still being created by Crossplane
- Rerun workflow after 5-10 minutes
- Check Crossplane XR status: `kubectl get staticwebsite SITE-NAME -o yaml`

## References

- [AWS IAM Roles for GitHub Actions](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)
- [S3 Bucket Policy Examples](https://docs.aws.amazon.com/AmazonS3/latest/userguide/example-bucket-policies.html)
- [CloudFront Permissions](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/access-control-overview.html)
- Platform Config: `config/platform-params.yaml` → `github.actionsRoleName`
