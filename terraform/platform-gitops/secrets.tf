################################################################################
# Kubernetes Secrets
# Managed by Terraform, consumed by platform applications
################################################################################

# ArgoCD Repository Credentials (GitHub token)
resource "kubernetes_secret" "argocd_repo" {
  metadata {
    name      = "repo-id-platform"
    namespace = local.argocd.namespace
    labels = {
      "app.kubernetes.io/managed-by"   = "terraform"
      "app.kubernetes.io/part-of"      = "platform-gitops"
      "argocd.argoproj.io/secret-type" = "repository"
    }
    annotations = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    url      = local.platform_repo_url
    username = local.github_username
    password = var.github_token
    type     = "git"
  }

  type = "Opaque"

  depends_on = [
    helm_release.argocd
  ]
}

# ArgoCD Repository Credentials (repo-creds for ApplicationSet git generator)
resource "kubernetes_secret" "argocd_repo_creds" {
  metadata {
    name      = "repo-creds-github"
    namespace = local.argocd.namespace
    labels = {
      "app.kubernetes.io/managed-by"   = "terraform"
      "app.kubernetes.io/part-of"      = "platform-gitops"
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }
    annotations = {
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }
  }

  data = {
    url      = local.github_repo_creds_url
    username = local.github_username
    password = var.github_token
    type     = "git"
  }

  type = "Opaque"

  depends_on = [
    helm_release.argocd
  ]
}

# Backstage Cognito Credentials
resource "random_password" "backstage_auth_session_secret" {
  length  = 64
  special = true
}

resource "kubernetes_secret" "backstage_cognito" {
  metadata {
    name      = "backstage-cognito"
    namespace = "backstage"
    labels = {
      "app.kubernetes.io/name"       = "backstage"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "platform-gitops"
    }
  }

  data = {
    COGNITO_CLIENT_ID     = aws_cognito_user_pool_client.backstage.id
    COGNITO_CLIENT_SECRET = aws_cognito_user_pool_client.backstage.client_secret
    COGNITO_ISSUER        = "https://cognito-idp.${local.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
    AUTH_SESSION_SECRET   = random_password.backstage_auth_session_secret.result
  }

  type = "Opaque"

  depends_on = [
    helm_release.argocd,
    kubernetes_namespace.backstage
  ]
}

# PostgreSQL Credentials (development environment)
# TODO: Replace with Sealed Secrets or External Secrets Operator for production
resource "kubernetes_secret" "backstage_postgresql" {
  metadata {
    name      = "backstage-postgresql"
    namespace = "backstage"
    labels = {
      "app.kubernetes.io/name"       = "backstage"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "platform-gitops"
    }
  }

  data = {
    POSTGRES_HOST     = "backstage-postgresql"
    POSTGRES_PORT     = "5432"
    POSTGRES_USER     = "backstage"
    POSTGRES_PASSWORD = "changeme-use-sealed-secrets"
    POSTGRES_DB       = "backstage"
  }

  type = "Opaque"

  depends_on = [
    helm_release.argocd,
    kubernetes_namespace.backstage
  ]
}
