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

variable "github_app_id" {
  description = "GitHub App ID for ArgoCD SCM Provider (optional)"
  type        = string
  default     = null
  sensitive   = true
}

variable "github_app_installation_id" {
  description = "GitHub App Installation ID for ArgoCD SCM Provider (optional)"
  type        = string
  default     = null
  sensitive   = true
}

variable "github_app_private_key" {
  description = "GitHub App private key PEM for ArgoCD SCM Provider (optional)"
  type        = string
  default     = null
  sensitive   = true
}

