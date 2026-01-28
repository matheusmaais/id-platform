################################################################################
# ArgoCD Application - App of Apps Pattern
################################################################################

resource "kubectl_manifest" "platform_apps" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "platform-apps"
      namespace = local.argocd.namespace
      finalizers = [
        "resources-finalizer.argocd.argoproj.io"
      ]
    }
    spec = {
      project = "default"

      source = {
        repoURL        = local.platform_repo_url
        targetRevision = local.platform_repo_branch
        path           = "argocd-apps/platform"
      }

      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = local.argocd.namespace
      }

      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }

        syncOptions = [
          "CreateNamespace=true"
        ]

        retry = {
          limit = 5
          backoff = {
            duration    = "5s"
            factor      = 2
            maxDuration = "3m"
          }
        }
      }
    }
  })

  depends_on = [
    helm_release.argocd
  ]
}
