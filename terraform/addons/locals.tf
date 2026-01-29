locals {
  # Karpenter Controller
  karpenter_namespace       = "karpenter"
  karpenter_service_account = "karpenter"
  karpenter_version         = "1.8.6"

  # Bootstrap Node Group (where Karpenter runs)
  bootstrap_node_group_name = "default-node-group"

  # EC2NodeClass Configuration - ARM64 (Graviton)
  node_class_arm64 = {
    name       = "karpenter-arm64"
    ami_family = "AL2023"
    ami_alias  = "al2023@latest"
    disk_size  = "50Gi"
  }

  # EC2NodeClass Configuration - AMD64 (x86_64) - COMMENTED OUT
  node_class_amd64 = {
    name       = "karpenter-amd64"
    ami_family = "AL2023"
    ami_alias  = "al2023@latest"
    disk_size  = "50Gi"
  }

  # NodePool Configuration - ARM64 (default)
  node_pool_arm64 = {
    name = "karpenter-arm64"
    requirements = {
      arch                = ["arm64"]
      os                  = ["linux"]
      capacity_type       = ["spot"]
      instance_category   = ["t"]
      instance_generation = "4" # t4g
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

  # NodePool Configuration - AMD64 - COMMENTED OUT
  # To enable: uncomment resources below + apply terraform
  node_pool_amd64 = {
    name = "karpenter-amd64"
    requirements = {
      arch                = ["amd64"]
      os                  = ["linux"]
      capacity_type       = ["spot"]
      instance_category   = ["t"]
      instance_generation = "3" # t3
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
    weight = 5 # Lower priority than ARM64
  }
}
