locals {
  # Karpenter
  karpenter_namespace       = "karpenter"
  karpenter_service_account = "karpenter"

  # Bootstrap Node Group Configuration
  bootstrap_node_group = {
    name           = "default-node-group"
    ami_type       = "AL2023_ARM_64_STANDARD"
    instance_types = ["t4g.medium"]
    capacity_type  = "ON_DEMAND"
    min_size       = 1
    max_size       = 2
    desired_size   = 1
    disk_size_gb   = 50
  }
}
