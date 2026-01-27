################################################################################
# Kubernetes Namespaces
# Managed by Terraform to avoid ordering issues with Secrets
################################################################################

resource "kubernetes_namespace" "backstage" {
  metadata {
    name = "backstage"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "platform-gitops"
    }
  }
}
