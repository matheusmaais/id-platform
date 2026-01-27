variable "cognito_admin_temp_password" {
  description = "Temporary password for default admin user (will be forced to change on first login)"
  type        = string
  default     = null
  sensitive   = true
}

variable "github_token" {
  description = "GitHub token for ArgoCD repository access"
  type        = string
  sensitive   = true
}

