output "cluster_id" {
  description = "EKS cluster ID"
  value       = module.eks.cluster_id
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "OIDC issuer URL for IRSA"
  value       = module.eks.cluster_oidc_issuer_url
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "bootstrap_node_group_id" {
  description = "Bootstrap node group ID"
  value       = module.eks.eks_managed_node_groups["bootstrap"].node_group_id
}

output "bootstrap_node_role_name" {
  description = "Bootstrap node IAM role name"
  value       = module.eks.eks_managed_node_groups["bootstrap"].iam_role_name
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "karpenter_role_arn" {
  description = "Karpenter IAM role ARN"
  value       = module.karpenter.iam_role_arn
}

output "karpenter_queue_name" {
  description = "Karpenter SQS queue name for spot interruption handling"
  value       = module.karpenter.queue_name
}

################################################################################
# Security Group Outputs
################################################################################

output "cluster_security_group_id" {
  description = "EKS cluster security group ID"
  value       = module.eks.cluster_security_group_id
}

output "node_security_group_id" {
  description = "EKS node security group ID"
  value       = module.eks.node_security_group_id
}

output "platform_alb_security_group_id" {
  description = "Shared platform ALB security group ID (for IngressGroup)"
  value       = aws_security_group.platform_alb.id
}

