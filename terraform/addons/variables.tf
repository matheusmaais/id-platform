variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "default_tags" {
  description = "Default tags for all resources"
  type        = map(string)
  default = {
    Project      = "IDP-POC"
    ManagedBy    = "Terraform"
    Environment  = "dev"
    Owner        = "Matheus Andrade"
    OwnerEmail   = "matheus.andrade@darede.com.br"
    Manager      = "Clayton Nogueira"
    ManagerEmail = "clayton.nogueira@darede.com.br"
  }
}
