################################################################################
# Karpenter - Node Autoscaling
# Why: Intelligent, fast node provisioning based on actual workload needs
# Replaces: Cluster Autoscaler (slower, less flexible)
################################################################################

################################################################################
# Karpenter IAM Role (IRSA)
################################################################################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.0"

  cluster_name = module.eks.cluster_name

  # Enable spot instance support
  enable_spot_termination = true
  enable_v1_permissions   = true

  # Node IAM role - reuse EKS managed node group role
  create_node_iam_role = false
  node_iam_role_arn    = module.eks.eks_managed_node_groups["bootstrap"].iam_role_arn

  # Access entry already created by EKS module for the node group
  create_access_entry = false

  # IRSA for Karpenter controller
  enable_irsa                     = true
  irsa_namespace_service_accounts = ["${local.karpenter_namespace}:${local.karpenter_service_account}"]
  irsa_oidc_provider_arn          = module.eks.oidc_provider_arn
}

################################################################################
# Security Group for Karpenter Nodes
################################################################################

resource "aws_security_group_rule" "karpenter_node_discovery" {
  description              = "Allow Karpenter node discovery"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = module.eks.cluster_security_group_id
  source_security_group_id = module.eks.node_security_group_id
}
