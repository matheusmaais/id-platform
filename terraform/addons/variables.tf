variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "default_tags" {
  description = "Default tags for all resources"
  type        = map(string)
  default = {
    Project     = "IDP-POC"
    ManagedBy   = "Terraform"
    Environment = "dev"
    # Add your organization's tags here
    # Owner        = "Your Name"
    # OwnerEmail   = "your.email@example.com"
  }
}
