locals {
  # Karpenter Controller
  karpenter_namespace       = "karpenter"
  karpenter_service_account = "karpenter"
  karpenter_version         = "1.8.6"

  # Bootstrap Node Group (where Karpenter runs)
  bootstrap_node_group_name = "default-node-group"

  # EC2NodeClass Configuration
  node_class = {
    name       = "karpenter-node-group"
    ami_family = "AL2023"
    ami_alias  = "al2023@latest"
    disk_size  = "50Gi"
  }

  # NodePool Configuration
  node_pool = {
    name = "karpenter-node-group"
    requirements = {
      arch                = ["arm64"]
      os                  = ["linux"]
      capacity_type       = ["spot"]
      instance_category   = ["t"]
      instance_generation = "3"
    }
    limits = {
      cpu    = "100"
      memory = "200Gi"
    }
    disruption = {
      consolidation_policy = "WhenEmpty"
      consolidate_after    = "1m"
      expire_after         = "720h"
      budget_nodes         = "10%"
    }
    weight = 10
  }
}
