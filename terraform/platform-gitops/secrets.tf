################################################################################
# Kubernetes Secrets
# Managed by Terraform, consumed by platform applications
################################################################################

# Backstage Cognito Credentials
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
  }

  type = "Opaque"

  depends_on = [
    helm_release.argocd
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
    helm_release.argocd
  ]
}
