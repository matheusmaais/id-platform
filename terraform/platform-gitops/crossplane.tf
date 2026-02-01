################################################################################
# Crossplane AWS Provider IAM Role (IRSA)
# 
# The AWS Provider creates ServiceAccounts dynamically with names like:
# - crossplane-provider-aws-*
# We use StringLike to match this pattern.
################################################################################

locals {
  crossplane = {
    namespace                = "crossplane-system"
    provider_service_account = "crossplane-provider-aws-*"
  }
}

data "aws_iam_policy_document" "crossplane_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.eks.outputs.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    # Use StringLike for wildcard matching of provider SA name
    condition {
      test     = "StringLike"
      variable = "${replace(data.aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:${local.crossplane.namespace}:${local.crossplane.provider_service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "crossplane" {
  name               = "${local.cluster_name}-crossplane"
  assume_role_policy = data.aws_iam_policy_document.crossplane_assume_role.json

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-crossplane"
    }
  )
}

################################################################################
# Crossplane IAM Policy
# 
# Scoped permissions for Static Website resources:
# - S3: Bucket creation and management
# - CloudFront: Distribution creation and management
# - Additional services can be added as needed
################################################################################

data "aws_iam_policy_document" "crossplane" {
  # S3 Bucket Management
  statement {
    sid    = "S3BucketManagement"
    effect = "Allow"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:GetBucketLocation",
      "s3:GetBucketTagging",
      "s3:PutBucketTagging",
      "s3:GetBucketPolicy",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:GetBucketPublicAccessBlock",
      "s3:PutBucketPublicAccessBlock",
      "s3:GetBucketVersioning",
      "s3:PutBucketVersioning",
      "s3:GetBucketCORS",
      "s3:PutBucketCORS",
      "s3:DeleteBucketCORS",
      "s3:GetBucketWebsite",
      "s3:PutBucketWebsite",
      "s3:DeleteBucketWebsite",
      "s3:GetBucketAcl",
      "s3:PutBucketAcl",
      "s3:GetBucketOwnershipControls",
      "s3:PutBucketOwnershipControls",
      "s3:GetAccelerateConfiguration",
      "s3:PutAccelerateConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:PutReplicationConfiguration",
      "s3:GetBucketLogging",
      "s3:PutBucketLogging",
      "s3:ListBucket",
      "s3:HeadBucket"
    ]
    resources = [
      "arn:aws:s3:::idp-*-static",
      "arn:aws:s3:::idp-*-static/*"
    ]
  }

  # CloudFront Distribution Management
  statement {
    sid    = "CloudFrontDistributionManagement"
    effect = "Allow"
    actions = [
      "cloudfront:CreateDistribution",
      "cloudfront:DeleteDistribution",
      "cloudfront:GetDistribution",
      "cloudfront:GetDistributionConfig",
      "cloudfront:UpdateDistribution",
      "cloudfront:TagResource",
      "cloudfront:UntagResource",
      "cloudfront:ListTagsForResource"
    ]
    resources = ["*"]
  }

  # CloudFront Origin Access Control
  statement {
    sid    = "CloudFrontOACManagement"
    effect = "Allow"
    actions = [
      "cloudfront:CreateOriginAccessControl",
      "cloudfront:DeleteOriginAccessControl",
      "cloudfront:GetOriginAccessControl",
      "cloudfront:GetOriginAccessControlConfig",
      "cloudfront:UpdateOriginAccessControl",
      "cloudfront:ListOriginAccessControls"
    ]
    resources = ["*"]
  }

  # CloudFront Cache Policies (read-only for managed policies)
  statement {
    sid    = "CloudFrontPoliciesRead"
    effect = "Allow"
    actions = [
      "cloudfront:GetCachePolicy",
      "cloudfront:ListCachePolicies",
      "cloudfront:GetOriginRequestPolicy",
      "cloudfront:ListOriginRequestPolicies",
      "cloudfront:GetResponseHeadersPolicy",
      "cloudfront:ListResponseHeadersPolicies"
    ]
    resources = ["*"]
  }

  # CloudFront Invalidation (for CI/CD)
  statement {
    sid    = "CloudFrontInvalidation"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation",
      "cloudfront:GetInvalidation",
      "cloudfront:ListInvalidations"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "crossplane" {
  name        = "${local.cluster_name}-crossplane"
  description = "IAM policy for Crossplane AWS Provider to manage S3 and CloudFront resources"
  policy      = data.aws_iam_policy_document.crossplane.json

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-crossplane"
    }
  )
}

resource "aws_iam_role_policy_attachment" "crossplane" {
  role       = aws_iam_role.crossplane.name
  policy_arn = aws_iam_policy.crossplane.arn
}

################################################################################
# Crossplane Namespace and ServiceAccount
# Created here so IRSA annotation has access to the role ARN
################################################################################

resource "kubernetes_namespace" "crossplane_system" {
  metadata {
    name = local.crossplane.namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "crossplane"
    }
  }
}

resource "kubernetes_service_account" "crossplane_provider_aws" {
  metadata {
    name      = "provider-aws"
    namespace = local.crossplane.namespace

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.crossplane.arn
    }

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "crossplane"
    }
  }

  depends_on = [kubernetes_namespace.crossplane_system]
}

################################################################################
# Output Crossplane Role ARN for ProviderConfig
################################################################################

output "crossplane_role_arn" {
  description = "ARN of the IAM role for Crossplane AWS Provider"
  value       = aws_iam_role.crossplane.arn
}
