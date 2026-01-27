variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "idp-poc-darede-cluster"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default = {
    Project   = "Internal Developer Platform"
    Terraform = "true"
  }
}

variable "cognito_admin_email" {
  description = "Email for default Cognito admin user"
  type        = string
  default     = "admin@timedevops.click"
}

variable "cognito_admin_temp_password" {
  description = "Temporary password for default admin user (will be forced to change on first login)"
  type        = string
  default     = "TempPass123!@#"
  sensitive   = true
}
