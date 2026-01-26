variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name (used for VPC naming and tagging)"
  type        = string
  default     = "platform-eks"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "default_tags" {
  description = "Default tags for all resources"
  type        = map(string)
  default = {
    Project     = "Platform-Rebuild"
    ManagedBy   = "Terraform"
    Environment = "dev"
  }
}
