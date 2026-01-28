################################################################################
# Platform Parameters ConfigMap
# Contains infrastructure-specific parameters consumed by all platform applications
# Managed by Terraform, referenced by ArgoCD ApplicationSets and Applications
################################################################################

resource "kubernetes_config_map" "platform_params" {
  metadata {
    name      = "platform-params"
    namespace = local.argocd.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "platform-gitops"
    }
  }

  data = {
    # Domain configuration
    DOMAIN           = local.domain
    ARGOCD_DOMAIN    = local.subdomains.argocd
    BACKSTAGE_DOMAIN = local.subdomains.backstage
    GRAFANA_DOMAIN   = local.subdomains.grafana

    # AWS configuration
    AWS_REGION     = data.aws_region.current.name
    AWS_ACCOUNT_ID = data.aws_caller_identity.current.account_id
    CLUSTER_NAME   = local.cluster_name

    # Cognito configuration
    COGNITO_ISSUER        = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.main.id}"
    COGNITO_USER_POOL_ID  = aws_cognito_user_pool.main.id
    COGNITO_HOSTED_UI_URL = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"

    # Shared ALB configuration (IngressGroup)
    ALB_GROUP_NAME        = local.shared_alb.group_name
    ALB_SECURITY_GROUP_ID = local.shared_alb.security_group_id

    # Route53
    HOSTED_ZONE_ID = data.aws_route53_zone.main.zone_id

    # ACM Certificate ARN
    ACM_CERTIFICATE_ARN = data.aws_acm_certificate.main.arn

    # Auth (Backstage) - keep file-driven via config/platform-params.yaml
    AUTH_ALLOWED_EMAIL_DOMAINS = join(",", local.allowed_email_domains)

    # GitHub (Scaffolder + ArgoCD AppSet)
    GITHUB_ORG               = local.github_org
    GITHUB_APP_NAME          = local.github_app_name
    GITHUB_REPO_PREFIX       = local.github_repo_prefix
    GITHUB_REPO_VISIBILITY   = local.github_repo_visibility
    GITHUB_SCM_AUTH          = local.github_scm_auth
    GITHUB_ACTIONS_ROLE_NAME = local.github_actions_role_name

    # Platform repo (templates + configuration)
    PLATFORM_REPO_URL    = local.platform_repo_url
    PLATFORM_REPO_BRANCH = local.platform_repo_branch

    # ECR Configuration (derived)
    ECR_REGISTRY = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
  }

  depends_on = [
    helm_release.argocd
  ]
}

# Copy platform-params to backstage namespace for app consumption
resource "kubernetes_config_map" "platform_params_backstage" {
  metadata {
    name      = "platform-params"
    namespace = "backstage"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "platform-gitops"
    }
  }

  data = kubernetes_config_map.platform_params.data

  depends_on = [
    kubernetes_namespace.backstage
  ]
}

# Data source for ACM certificate
data "aws_acm_certificate" "main" {
  domain   = local.domain
  statuses = ["ISSUED"]
}
