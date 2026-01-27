locals {
  # Domain Configuration
  domain = "timedevops.click"
  subdomains = {
    argocd    = "argocd.${local.domain}"
    backstage = "backstage.${local.domain}"
    grafana   = "grafana.${local.domain}"
  }

  # Shared ALB Configuration (IngressGroup)
  # All platform apps share a single ALB to reduce costs
  # See: docs/ARCHITECTURE-DECISIONS.md ADR-001
  shared_alb = {
    group_name    = "${var.environment}-platform"
    security_group_id = data.terraform_remote_state.eks.outputs.platform_alb_security_group_id
  }

  # Cognito Configuration
  cognito = {
    user_pool_name          = "${var.cluster_name}-user-pool"
    oauth_domain_prefix     = "idp-poc-darede"
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
    txt_owner_id    = var.cluster_name
    policy          = "upsert-only"
  }

  # Common Tags
  common_tags = merge(
    var.default_tags,
    {
      Stack       = "platform-gitops"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  )
}
