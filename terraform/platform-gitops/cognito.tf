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

  # Lambda trigger for Pre Token Generation V2
  # This adds cognito:groups claim to ID token for OIDC clients
  lambda_config {
    pre_token_generation_config {
      lambda_arn     = aws_lambda_function.pre_token_generation.arn
      lambda_version = "V2_0"
    }
  }

  tags = merge(
    local.common_tags,
    {
      Name = local.cognito.user_pool_name
    }
  )

  depends_on = [
    aws_lambda_permission.cognito_invoke
  ]
}

################################################################################
# Pre-Token Generation Lambda
# Adds cognito:groups claim to ID token for OIDC integration
################################################################################

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "pre_token_generation" {
  name               = "${local.cluster_name}-cognito-pre-token-gen"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-cognito-pre-token-gen"
    }
  )
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.pre_token_generation.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda function code
data "archive_file" "pre_token_generation" {
  type        = "zip"
  output_path = "${path.module}/lambda/pre_token_generation.zip"

  source {
    content  = <<-EOF
      exports.handler = async (event) => {
        // V2_0 Pre Token Generation Lambda
        // Adds cognito:groups to ID token claims for OIDC
        console.log('Event:', JSON.stringify(event, null, 2));
        
        const groups = event.request.groupConfiguration.groupsToOverride || [];
        
        // Return the response with groups claim added to ID token
        event.response = {
          claimsAndScopeOverrideDetails: {
            idTokenGeneration: {
              claimsToAddOrOverride: {
                "cognito:groups": JSON.stringify(groups)
              }
            },
            accessTokenGeneration: {
              claimsToAddOrOverride: {
                "cognito:groups": JSON.stringify(groups)
              }
            }
          }
        };
        
        console.log('Response:', JSON.stringify(event.response, null, 2));
        return event;
      };
    EOF
    filename = "index.js"
  }
}

resource "aws_lambda_function" "pre_token_generation" {
  function_name    = "${local.cluster_name}-cognito-pre-token-gen"
  filename         = data.archive_file.pre_token_generation.output_path
  source_code_hash = data.archive_file.pre_token_generation.output_base64sha256
  handler          = "index.handler"
  runtime          = "nodejs20.x"
  role             = aws_iam_role.pre_token_generation.arn
  timeout          = 10
  memory_size      = 128

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-cognito-pre-token-gen"
    }
  )
}

resource "aws_lambda_permission" "cognito_invoke" {
  statement_id  = "AllowCognitoInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pre_token_generation.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = "arn:aws:cognito-idp:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:userpool/*"
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
  id_token_validity      = 60 # 1 hour
  access_token_validity  = 60 # 1 hour
  refresh_token_validity = 30 # 30 days

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
# Cognito User Pool Client - Backstage
################################################################################

resource "aws_cognito_user_pool_client" "backstage" {
  name         = "backstage"
  user_pool_id = aws_cognito_user_pool.main.id

  # OAuth configuration
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "profile", "email"]

  # Callback URLs
  callback_urls = [
    "https://${local.subdomains.backstage}/api/auth/oidc/handler/frame",
    "http://localhost:7007/api/auth/oidc/handler/frame" # For local testing
  ]

  # Logout URLs
  logout_urls = [
    "https://${local.subdomains.backstage}",
    "http://localhost:7007"
  ]

  # Supported identity providers
  supported_identity_providers = ["COGNITO"]

  # Token validity
  id_token_validity      = 60 # 1 hour
  access_token_validity  = 60 # 1 hour
  refresh_token_validity = 30 # 30 days

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

  # Explicit auth flows
  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH"
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
  username     = local.cognito_admin_email

  attributes = {
    email          = local.cognito_admin_email
    email_verified = true
  }

  temporary_password = local.cognito_admin_temp_password

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
