# VPC remote state - read outputs from VPC module
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket  = "poc-idp-tfstate"
    key     = "vpc/terraform.tfstate"
    region  = "us-east-1"
    profile = "darede"
  }
}

