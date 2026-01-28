################################################################################
# App Platform (Phase 2)
# - AppProject "apps" to restrict workloads
# - ApplicationSet "workloads" to auto-discover repos in GitHub org
#
# IMPORTANT:
# - This is managed by Terraform (foundation), since ApplicationSet generator
#   fields (like github.organization) are not templated by ArgoCD itself.
# - Values are sourced from config/platform-params.yaml via locals.
################################################################################

resource "kubectl_manifest" "apps_project" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = "apps"
      namespace = local.argocd.namespace
      annotations = {
        "argocd.argoproj.io/sync-wave" = "5"
      }
      finalizers = [
        "resources-finalizer.argocd.argoproj.io",
      ]
    }
    spec = {
      description = "Applications created via Backstage scaffolder"

      sourceRepos = [
        "https://github.com/${local.github_org}/${local.github_repo_prefix}*",
      ]

      destinations = [
        {
          server    = "https://kubernetes.default.svc"
          namespace = "${local.github_repo_prefix}*"
        }
      ]

      clusterResourceWhitelist = [
        { group = "", kind = "Namespace" },
      ]

      namespaceResourceWhitelist = [
        { group = "", kind = "Service" },
        { group = "", kind = "ConfigMap" },
        { group = "", kind = "Secret" },
        { group = "", kind = "ServiceAccount" },
        { group = "apps", kind = "Deployment" },
        { group = "apps", kind = "StatefulSet" },
        { group = "apps", kind = "DaemonSet" },
        { group = "batch", kind = "Job" },
        { group = "batch", kind = "CronJob" },
        { group = "networking.k8s.io", kind = "Ingress" },
        { group = "networking.k8s.io", kind = "NetworkPolicy" },
        { group = "autoscaling", kind = "HorizontalPodAutoscaler" },
        { group = "policy", kind = "PodDisruptionBudget" },
        { group = "monitoring.coreos.com", kind = "ServiceMonitor" },
        { group = "monitoring.coreos.com", kind = "PodMonitor" },
      ]

      roles = [
        {
          name        = "developer"
          description = "Developer role for app management"
          policies = [
            "p, proj:apps:developer, applications, get, apps/*, allow",
            "p, proj:apps:developer, applications, sync, apps/*, allow",
          ]
          groups = ["developers"]
        },
        {
          name        = "admin"
          description = "Admin role with full control"
          policies = [
            "p, proj:apps:admin, applications, *, apps/*, allow",
          ]
          groups = ["argocd-admins"]
        }
      ]
    }
  })

  depends_on = [
    helm_release.argocd,
  ]
}

resource "kubectl_manifest" "workloads_appset" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "ApplicationSet"
    metadata = {
      name      = "workloads"
      namespace = local.argocd.namespace
      annotations = {
        "argocd.argoproj.io/sync-wave" = "10"
      }
    }
    spec = merge(
      {
        goTemplate        = true
        goTemplateOptions = ["missingkey=error"]
        generators = [
          {
            scmProvider = {
              github = merge(
                {
                  organization = local.github_org
                  allBranches  = false
                },
                local.github_app_enabled ? {
                  appSecretName = kubernetes_secret.argocd_github_app_creds[0].metadata[0].name
                  } : {
                  tokenRef = {
                    secretName = kubernetes_secret.argocd_scm_token.metadata[0].name
                    key        = "token"
                  }
                }
              )
              filters = [
                {
                  repositoryMatch = "^${local.github_repo_prefix}.*"
                  pathsExist      = ["k8s"]
                }
              ]
            }
          }
        ]
        template = {
          metadata = {
            name      = "{{.repository}}"
            namespace = local.argocd.namespace
            labels = {
              "app.kubernetes.io/name"       = "{{.repository}}"
              "app.kubernetes.io/managed-by" = "applicationset"
              "platform.darede.io/workload"  = "true"
            }
            annotations = {
              repo_url    = "{{.url}}"
              repo_branch = "{{.branch}}"
            }
          }
          spec = {
            project = "apps"
            source = {
              repoURL        = "{{.url}}"
              targetRevision = "{{.branch}}"
              path           = "k8s"
            }
            destination = {
              server    = "https://kubernetes.default.svc"
              namespace = "{{.repository}}"
            }
            syncPolicy = {
              automated = {
                prune      = true
                selfHeal   = true
                allowEmpty = false
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
            ignoreDifferences = [
              {
                group        = "apps"
                kind         = "Deployment"
                jsonPointers = ["/spec/replicas"]
              }
            ]
          }
        }
      },
      {}
    )
  })

  lifecycle {
    precondition {
      condition     = local.github_scm_auth != "app" || local.github_app_enabled
      error_message = "github.scmAuth is set to 'app' but GitHub App credentials (TF_VAR_github_app_*) are not configured."
    }
  }

  depends_on = [
    kubectl_manifest.apps_project,
    helm_release.argocd,
    kubernetes_secret.argocd_scm_token,
  ]
}

