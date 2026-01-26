################################################################################
# Karpenter Helm Chart
################################################################################

resource "helm_release" "karpenter" {
  namespace        = local.karpenter_namespace
  create_namespace = true

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = local.karpenter_version

  # ECR public authentication
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password

  values = [
    yamlencode({
      serviceAccount = {
        name = local.karpenter_service_account
        annotations = {
          "eks.amazonaws.com/role-arn" = data.terraform_remote_state.eks.outputs.karpenter_role_arn
        }
      }

      settings = {
        clusterName       = data.terraform_remote_state.eks.outputs.cluster_name
        clusterEndpoint   = data.terraform_remote_state.eks.outputs.cluster_endpoint
        interruptionQueue = data.terraform_remote_state.eks.outputs.karpenter_queue_name
      }

      # Run on default node group
      tolerations = [{
        key      = "node-role.kubernetes.io/${local.bootstrap_node_group_name}"
        operator = "Exists"
        effect   = "NoSchedule"
      }]

      nodeSelector = {
        role = local.bootstrap_node_group_name
      }

      # Resources
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "1000m"
          memory = "1Gi"
        }
      }

      # Replica count
      replicas = 1 # Single replica for dev, increase for production
    })
  ]
}

################################################################################
# Karpenter EC2NodeClass
# Defines the EC2 configuration for nodes
################################################################################

resource "kubectl_manifest" "karpenter_node_class" {
  depends_on = [helm_release.karpenter]

  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = local.node_class.name
    }
    spec = {
      # AMI Selection - AL2023 ARM64 optimized
      amiFamily = local.node_class.ami_family
      amiSelectorTerms = [{
        alias = local.node_class.ami_alias
      }]

      # Subnet selection - use private subnets with Karpenter tag
      subnetSelectorTerms = [{
        tags = {
          "karpenter.sh/discovery" = data.terraform_remote_state.eks.outputs.cluster_name
        }
      }]

      # Security group selection
      securityGroupSelectorTerms = [{
        tags = {
          "karpenter.sh/discovery" = data.terraform_remote_state.eks.outputs.cluster_name
        }
      }]

      # IAM role for nodes
      role = data.terraform_remote_state.eks.outputs.bootstrap_node_role_name

      # Block device mappings
      blockDeviceMappings = [{
        deviceName = "/dev/xvda"
        ebs = {
          volumeSize          = local.node_class.disk_size
          volumeType          = "gp3"
          encrypted           = true
          deleteOnTermination = true
        }
      }]

      # Metadata options
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpProtocolIPv6        = "disabled"
        httpPutResponseHopLimit = 2
        httpTokens              = "required" # IMDSv2 required
      }

      # Tags
      tags = merge(
        var.default_tags,
        {
          "Name"                   = "${data.terraform_remote_state.eks.outputs.cluster_name}-karpenter"
          "karpenter.sh/discovery" = data.terraform_remote_state.eks.outputs.cluster_name
        }
      )
    }
  })
}

################################################################################
# Karpenter NodePool
# Defines when and how to provision nodes
################################################################################

resource "kubectl_manifest" "karpenter_node_pool" {
  depends_on = [kubectl_manifest.karpenter_node_class]

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = local.node_pool.name
    }
    spec = {
      # Template for nodes
      template = {
        metadata = {
          labels = {
            "node.kubernetes.io/managed-by" = "karpenter"
          }
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = local.node_class.name
          }

          # Requirements - what kinds of nodes can be created
          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = local.node_pool.requirements.arch
            },
            {
              key      = "kubernetes.io/os"
              operator = "In"
              values   = local.node_pool.requirements.os
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = local.node_pool.requirements.capacity_type
            },
            {
              key      = "karpenter.k8s.aws/instance-category"
              operator = "In"
              values   = local.node_pool.requirements.instance_category
            },
            {
              key      = "karpenter.k8s.aws/instance-generation"
              operator = "Gt"
              values   = [local.node_pool.requirements.instance_generation]
            }
          ]
        }
      }

      # Limits - prevent runaway scaling
      limits = {
        cpu    = local.node_pool.limits.cpu
        memory = local.node_pool.limits.memory
      }

      # Disruption budget
      disruption = {
        consolidationPolicy = local.node_pool.disruption.consolidation_policy
        consolidateAfter    = local.node_pool.disruption.consolidate_after
        expireAfter         = local.node_pool.disruption.expire_after

        budgets = [{
          nodes = local.node_pool.disruption.budget_nodes
        }]
      }

      # Weight - lower number = higher priority
      weight = local.node_pool.weight
    }
  })
}
