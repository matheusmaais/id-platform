variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "platform-eks"
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.34" # Latest stable as of Jan 2026
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
