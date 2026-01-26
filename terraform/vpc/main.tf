################################################################################
# VPC Module
# Uses community-standard terraform-aws-modules/vpc
# Why: Proven, maintained, follows AWS best practices
################################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]      # /20 subnets
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)] # /24 subnets

  # Single NAT Gateway for cost optimization
  # Why: Dev environment doesn't need multi-AZ HA for NAT
  enable_nat_gateway   = true
  single_nat_gateway   = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  # EKS-required subnet tags
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
    # Karpenter discovery tag
    "karpenter.sh/discovery"                      = var.cluster_name
  }
}
