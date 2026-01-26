# EKS remote state - read outputs from EKS module
data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket  = "poc-idp-tfstate"
    key     = "eks/terraform.tfstate"
    region  = "us-east-1"
    profile = "darede"
  }
}

# EKS cluster authentication
data "aws_eks_cluster_auth" "cluster" {
  name = data.terraform_remote_state.eks.outputs.cluster_name
}

# ECR public authentication for Karpenter Helm chart
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}
