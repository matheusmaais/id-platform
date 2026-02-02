locals {
  platform_config = yamldecode(file("${path.module}/../../config/platform-params.yaml"))

  region                      = local.platform_config.infrastructure.awsRegion
  environment                 = local.platform_config.infrastructure.environment
  cluster_name                = local.platform_config.infrastructure.clusterName
  domain                      = local.platform_config.infrastructure.domain
  default_tags                = local.platform_config.tags
  cognito_admin_email         = local.platform_config.identity.cognitoAdminEmail
  cognito_admin_temp_password = var.cognito_admin_temp_password
  platform_repo_url           = local.platform_config.repository.url
  platform_repo_branch        = local.platform_config.repository.branch
  github_username             = "x-access-token"
  github_repo_creds_url       = element(regexall("^https?://[^/]+", local.platform_repo_url), 0)
  github_org                  = local.platform_config.github.org
  github_repo_prefix          = local.platform_config.github.appRepoPrefix
  github_repo_regex           = try(local.platform_config.github.repoRegex, "^${local.platform_config.github.appRepoPrefix}.*$")
  # Exclude platform repo (idp-platform) from workload discovery. RE2-compatible: no lookahead;
  # "platform" is 8 chars, so we match suffix 1-7 or 9+ chars to exclude only idp-platform.
  workloads_repo_regex        = "^idp-(?:[a-z0-9-]{1,7}|[a-z0-9-]{9,})$"
  github_repo_visibility      = try(local.platform_config.github.appRepoVisibility, "private")
  github_scm_auth             = try(local.platform_config.github.scmAuth, "token")
  github_app_name             = try(local.platform_config.github.appName, "")
  github_actions_role_name    = try(local.platform_config.github.actionsRoleName, "github-actions-ecr-push")
  github_app_enabled          = var.github_app_id != null && var.github_app_installation_id != null && var.github_app_private_key != null
  apps_manifests_path         = try(local.platform_config.apps.manifestsPath, "k8s")
  apps_namespace_strategy     = try(local.platform_config.apps.namespace.strategy, "per-app")
  apps_namespace_template     = try(local.platform_config.apps.namespace.template, "{{appName}}")
  alb_shared_group_name       = try(local.platform_config.alb.sharedGroupName, local.platform_config.infrastructure.albGroupName)
  alb_scheme                  = try(local.platform_config.alb.scheme, "internet-facing")
  alb_target_type             = try(local.platform_config.alb.targetType, "ip")
  ci_auth_mode                = try(local.platform_config.ci.authMode, "static-keys")
  ci_ecr_repo_prefix          = try(local.platform_config.ci.ecrRepoPrefix, local.platform_config.github.appRepoPrefix)
  ci_image_tag_strategy       = try(local.platform_config.ci.imageTagStrategy, "sha")
  app_default_arch            = try(local.platform_config.apps.defaults.arch, "arm64")
  build_platform_arm64        = try(local.platform_config.ci.build.platforms.arm64, "linux/arm64")
  build_platform_amd64        = try(local.platform_config.ci.build.platforms.amd64, "linux/amd64")
  build_platform_multi        = try(local.platform_config.ci.build.platforms.multi, "linux/arm64,linux/amd64")
  scheduling_arch_label_key   = try(local.platform_config.scheduling.archLabelKey, "kubernetes.io/arch")
  scheduling_arm_value        = try(local.platform_config.scheduling.armValue, "arm64")
  scheduling_amd_value        = try(local.platform_config.scheduling.amdValue, "amd64")
  allowed_email_domains = distinct(concat(
    try(local.platform_config.identity.allowedEmailDomains, []),
    [local.domain, split("@", local.cognito_admin_email)[1]],
  ))

  # Domain Configuration
  subdomains = {
    argocd    = "argocd.${local.domain}"
    backstage = "backstage.${local.domain}"
    grafana   = "grafana.${local.domain}"
  }

  # Shared ALB Configuration (IngressGroup)
  # All platform apps share a single ALB to reduce costs
  # See: docs/ARCHITECTURE-DECISIONS.md ADR-001
  shared_alb = {
    group_name        = local.alb_shared_group_name
    security_group_id = data.terraform_remote_state.eks.outputs.platform_alb_security_group_id
  }

  # Cognito Configuration
  cognito = {
    user_pool_name          = "${local.cluster_name}-user-pool"
    oauth_domain_prefix     = "idp-${local.environment}-platform"
    argocd_client_name      = "argocd"
    admin_group_name        = "argocd-admins"
    admin_group_description = "ArgoCD Administrators with full access"
  }

  # AWS Load Balancer Controller
  # Chart v1.17.1 (9 Jan 2026)
  aws_lb_controller = {
    namespace       = "kube-system"
    service_account = "aws-load-balancer-controller"
    chart_version   = "1.17.1"
  }

  # ArgoCD Configuration
  # Chart v9.3.5 (23 Jan 2026)
  argocd = {
    namespace     = "argocd"
    chart_version = "9.3.5"
  }

  # External-DNS Configuration
  # Chart v1.20.0 (2 Jan 2026)
  external_dns = {
    namespace       = "external-dns"
    service_account = "external-dns"
    chart_version   = "1.20.0"
    txt_owner_id    = local.cluster_name
    policy          = "upsert-only"
  }

  # Common Tags
  common_tags = merge(
    local.default_tags,
    {
      Stack       = "platform-gitops"
      ManagedBy   = "terraform"
      Environment = local.environment
    }
  )
}
