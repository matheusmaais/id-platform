################################################################################
# Cognito Outputs
################################################################################

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.main.arn
}

output "cognito_user_pool_endpoint" {
  description = "Cognito User Pool Endpoint"
  value       = aws_cognito_user_pool.main.endpoint
}

output "cognito_domain" {
  description = "Cognito OAuth Domain"
  value       = aws_cognito_user_pool_domain.main.domain
}

output "cognito_hosted_ui_url" {
  description = "Cognito Hosted UI URL"
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
}

output "cognito_issuer" {
  description = "Cognito OIDC Issuer URL"
  value       = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "cognito_argocd_client_id" {
  description = "Cognito ArgoCD Client ID"
  value       = aws_cognito_user_pool_client.argocd.id
}

output "cognito_argocd_client_secret" {
  description = "Cognito ArgoCD Client Secret"
  value       = aws_cognito_user_pool_client.argocd.client_secret
  sensitive   = true
}

################################################################################
# ArgoCD Outputs
################################################################################

output "argocd_url" {
  description = "ArgoCD Server URL"
  value       = "https://${local.subdomains.argocd}"
}

output "argocd_namespace" {
  description = "ArgoCD Namespace"
  value       = local.argocd.namespace
}

################################################################################
# Route53 Outputs
################################################################################

output "hosted_zone_id" {
  description = "Route53 Hosted Zone ID"
  value       = data.aws_route53_zone.main.zone_id
}

output "domain" {
  description = "Primary Domain"
  value       = local.domain
}

################################################################################
# IAM Outputs
################################################################################

output "aws_lb_controller_role_arn" {
  description = "AWS Load Balancer Controller IAM Role ARN"
  value       = aws_iam_role.aws_lb_controller.arn
}

output "external_dns_role_arn" {
  description = "External-DNS IAM Role ARN"
  value       = aws_iam_role.external_dns.arn
}

################################################################################
# Login Credentials
################################################################################

output "argocd_admin_credentials" {
  description = "ArgoCD Admin Credentials"
  value = {
    url              = "https://${local.subdomains.argocd}"
    username         = "admin"
    password_command = "kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
  }
}

output "create_admin_user_command" {
  description = "Command to fetch ArgoCD admin password"
  value       = "kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
}

output "cognito_admin_credentials" {
  description = "Cognito Admin User Credentials (SSO Login)"
  value = {
    url                = "https://${local.subdomains.argocd}"
    login_method       = "LOG IN VIA COGNITO"
    email              = local.cognito_admin_email
    temporary_password = local.cognito_admin_temp_password
    note               = "Password must be changed on first login"
  }
  sensitive = true
}

################################################################################
# Backstage Outputs
################################################################################

output "backstage_url" {
  description = "Backstage URL"
  value       = "https://${local.subdomains.backstage}"
}

output "backstage_cognito_client_id" {
  description = "Cognito Backstage Client ID"
  value       = aws_cognito_user_pool_client.backstage.id
}

output "backstage_cognito_client_secret" {
  description = "Cognito Backstage Client Secret"
  value       = aws_cognito_user_pool_client.backstage.client_secret
  sensitive   = true
}

################################################################################
# Platform Configuration
################################################################################

output "platform_params_configmap" {
  description = "Platform parameters ConfigMap name"
  value       = kubernetes_config_map.platform_params.metadata[0].name
}
