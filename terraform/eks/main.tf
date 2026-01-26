################################################################################
# EKS Cluster
# Uses terraform-aws-modules/eks - community standard
# Why: Proven module, handles IRSA, IAM, security best practices
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Endpoint configuration
  # Why: Public + private allows external access while keeping node traffic private
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Enable IRSA (IAM Roles for Service Accounts)
  # Why: Best practice for pod-level IAM permissions
  enable_irsa = true

  # Cluster creator admin permissions
  # Why: Allow current user to access cluster via kubectl
  enable_cluster_creator_admin_permissions = true

  # VPC configuration from remote state
  vpc_id     = data.terraform_remote_state.vpc.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.vpc.outputs.private_subnet_ids

  # Control plane logging
  # Why: Essential for troubleshooting
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # EKS Add-ons - minimal set
  cluster_addons = {
    coredns = {
      most_recent = true
      # Tolerate bootstrap node taint so CoreDNS can schedule
      configuration_values = jsonencode({
        tolerations = [
          {
            key      = "node-role.kubernetes.io/${local.bootstrap_node_group.name}"
            operator = "Exists"
            effect   = "NoSchedule"
          }
        ]
        nodeSelector = {
          role = local.bootstrap_node_group.name
        }
      })
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
      # Enable prefix delegation for more IPs per node
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
        }
      })
    }
  }

  # Bootstrap node group
  # Why: Karpenter needs existing capacity to run (chicken-egg problem)
  # This node group hosts Karpenter itself, then Karpenter manages all other workloads
  eks_managed_node_groups = {
    bootstrap = {
      name = local.bootstrap_node_group.name

      # ARM64 Graviton instances - Cost-effective, modern, good performance
      ami_type       = local.bootstrap_node_group.ami_type
      instance_types = local.bootstrap_node_group.instance_types

      # On-demand only for stability - Bootstrap nodes must be reliable
      capacity_type = local.bootstrap_node_group.capacity_type

      # Minimal scaling - Only need capacity for core platform tools
      min_size     = local.bootstrap_node_group.min_size
      max_size     = local.bootstrap_node_group.max_size
      desired_size = local.bootstrap_node_group.desired_size

      # Taint to prevent workloads from scheduling here
      taints = [{
        key    = "node-role.kubernetes.io/${local.bootstrap_node_group.name}"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]

      labels = {
        role = local.bootstrap_node_group.name
      }

      # Block device configuration
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = local.bootstrap_node_group.disk_size_gb
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      # Allow SSM for debugging
      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
    }
  }

  # Allow access from current machine
  cluster_security_group_additional_rules = {
    ingress_workstation = {
      description = "Workstation access"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"] # Consider restricting in production
    }
  }

  # Tag node security group for Karpenter discovery
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
}

################################################################################
# Bootstrap Node Group Documentation
################################################################################
# The bootstrap node group exists to solve the Karpenter chicken-egg problem:
# - Karpenter needs to run IN the cluster to provision nodes
# - But the cluster needs nodes to run Karpenter
#
# Solution:
# 1. Bootstrap nodes provide initial capacity
# 2. Karpenter deploys to bootstrap nodes (tolerates taint)
# 3. Karpenter provisions nodes for all other workloads
# 4. Bootstrap nodes remain running only for core platform tools
#
# Why ARM64 (Graviton):
# - 20% better price/performance vs x86
# - Good availability
# - Supported by all modern platform tools
#
# Why NoSchedule taint:
# - Forces workloads to use Karpenter-managed nodes
# - Keeps bootstrap nodes available for platform tools
# - Prevents resource contention
################################################################################
