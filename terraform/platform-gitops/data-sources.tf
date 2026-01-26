################################################################################
# EKS Cluster Data Sources
################################################################################

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = "poc-idp-tfstate"
    key    = "eks/terraform.tfstate"
    region = "us-east-1"
  }
}

data "aws_eks_cluster" "main" {
  name = data.terraform_remote_state.eks.outputs.cluster_name
}

data "aws_eks_cluster_auth" "main" {
  name = data.terraform_remote_state.eks.outputs.cluster_name
}

################################################################################
# Route53 Hosted Zone
################################################################################

data "aws_route53_zone" "main" {
  name         = local.domain
  private_zone = false
}

################################################################################
# ACM Certificate
################################################################################

data "aws_acm_certificate" "wildcard" {
  domain      = "*.${local.domain}"
  statuses    = ["ISSUED"]
  most_recent = true
}

################################################################################
# VPC Data from Remote State
################################################################################

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "poc-idp-tfstate"
    key    = "vpc/terraform.tfstate"
    region = "us-east-1"
  }
}

################################################################################
# Current AWS Account and Region
################################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
