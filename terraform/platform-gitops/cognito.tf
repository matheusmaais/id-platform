################################################################################
# Cognito User Pool
################################################################################

resource "aws_cognito_user_pool" "main" {
  name = local.cognito.user_pool_name

  # Email-based authentication
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Password policy
  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  # MFA configuration (optional but valid)
  mfa_configuration = "OPTIONAL"

  software_token_mfa_configuration {
    enabled = true
  }

  # Account recovery
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # User attribute schema
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 5
      max_length = 255
    }
  }

  # Email configuration
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  # Admin create user config
  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  # User pool add-ons
  user_pool_add_ons {
    advanced_security_mode = "ENFORCED"
  }

  tags = merge(
    local.common_tags,
    {
      Name = local.cognito.user_pool_name
    }
  )
}

################################################################################
# Cognito User Pool Domain
################################################################################

resource "aws_cognito_user_pool_domain" "main" {
  domain       = local.cognito.oauth_domain_prefix
  user_pool_id = aws_cognito_user_pool.main.id
}

################################################################################
# Cognito User Pool Client - ArgoCD
################################################################################

resource "aws_cognito_user_pool_client" "argocd" {
  name         = local.cognito.argocd_client_name
  user_pool_id = aws_cognito_user_pool.main.id

  # OAuth configuration
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "profile", "email"]

  # Callback URLs
  callback_urls = [
    "https://${local.subdomains.argocd}/api/dex/callback",
    "http://localhost:8080/api/dex/callback" # For local testing
  ]

  # Logout URLs
  logout_urls = [
    "https://${local.subdomains.argocd}",
    "http://localhost:8080"
  ]

  # Supported identity providers
  supported_identity_providers = ["COGNITO"]

  # Token validity
  id_token_validity      = 60  # 1 hour
  access_token_validity  = 60  # 1 hour
  refresh_token_validity = 30  # 30 days

  token_validity_units {
    id_token      = "minutes"
    access_token  = "minutes"
    refresh_token = "days"
  }

  # Prevent secret rotation breaking deployments
  generate_secret = true

  # Read/write attributes
  read_attributes  = ["email", "email_verified", "preferred_username"]
  write_attributes = ["email", "preferred_username"]

  # Explicit attribute mapping for groups claim
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]
}

################################################################################
# Cognito User Pool Group - ArgoCD Admins
################################################################################

resource "aws_cognito_user_group" "argocd_admins" {
  name         = local.cognito.admin_group_name
  user_pool_id = aws_cognito_user_pool.main.id
  description  = local.cognito.admin_group_description
  precedence   = 1
}

################################################################################
# Default Admin User
# Created automatically on first deployment
################################################################################

resource "aws_cognito_user" "admin" {
  user_pool_id = aws_cognito_user_pool.main.id
  username     = var.cognito_admin_email

  attributes = {
    email          = var.cognito_admin_email
    email_verified = true
  }

  temporary_password = var.cognito_admin_temp_password

  # Force password change on first login
  message_action = "SUPPRESS"

  lifecycle {
    ignore_changes = [
      temporary_password,
      attributes["email_verified"]
    ]
  }
}

resource "aws_cognito_user_in_group" "admin_in_argocd_admins" {
  user_pool_id = aws_cognito_user_pool.main.id
  group_name   = aws_cognito_user_group.argocd_admins.name
  username     = aws_cognito_user.admin.username
}
