################################################################################
# ArgoCD ALB Security Group
################################################################################

resource "aws_security_group" "argocd_alb" {
  name        = "${var.cluster_name}-argocd-alb"
  description = "Security group for ArgoCD ALB"
  vpc_id      = data.terraform_remote_state.vpc.outputs.vpc_id

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All traffic to VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.terraform_remote_state.vpc.outputs.vpc_cidr]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-argocd-alb"
    }
  )
}

# Get node security group by EKS cluster tag
data "aws_security_groups" "node" {
  filter {
    name   = "vpc-id"
    values = [data.terraform_remote_state.vpc.outputs.vpc_id]
  }

  filter {
    name   = "group-name"
    values = ["*-node-*"]
  }

  filter {
    name   = "tag:aws:eks:cluster-name"
    values = [data.aws_eks_cluster.main.name]
  }
}

# Allow ALB to reach pods in the cluster (cluster security group)
resource "aws_security_group_rule" "argocd_alb_to_cluster" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.argocd_alb.id
  security_group_id        = data.aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
  description              = "Allow ArgoCD ALB to reach ArgoCD server pods"
}

# Allow ALB to reach pods on nodes (node security group)
resource "aws_security_group_rule" "argocd_alb_to_nodes" {
  count                    = length(data.aws_security_groups.node.ids) > 0 ? 1 : 0
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.argocd_alb.id
  security_group_id        = data.aws_security_groups.node.ids[0]
  description              = "Allow ArgoCD ALB to reach ArgoCD server pods on nodes"
}

################################################################################
# ArgoCD Helm Release with Cognito OIDC
################################################################################

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = local.argocd.chart_version
  namespace        = local.argocd.namespace
  create_namespace = true

  values = [
    yamlencode({
      global = {
        domain = local.subdomains.argocd
      }

      configs = {
        # ConfigMap - Dex OIDC configuration
        cm = {
          # Server URL
          url = "https://${local.subdomains.argocd}"

          # OIDC configuration
          "dex.config" = yamlencode({
            connectors = [
              {
                type = "oidc"
                id   = "cognito"
                name = "AWS Cognito"
                config = {
                  issuer       = "https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.main.id}"
                  clientID     = aws_cognito_user_pool_client.argocd.id
                  clientSecret = aws_cognito_user_pool_client.argocd.client_secret
                  redirectURI  = "https://${local.subdomains.argocd}/api/dex/callback"

                  # Request specific scopes
                  scopes = ["openid", "profile", "email"]

                  # Claim mappings
                  claimMapping = {
                    groups = "cognito:groups"
                  }

                  # User info from ID token
                  getUserInfo = true
                }
              }
            ]
          })

          # Admin enabled (can also use SSO)
          "admin.enabled" = "true"

          # Application resource tracking
          "application.resourceTrackingMethod" = "annotation"
        }

        # RBAC Configuration
        rbac = {
          # RBAC policy
          "policy.csv" = <<-EOT
            # ArgoCD Admins group gets admin role
            g, ${local.cognito.admin_group_name}, role:admin
            
            # Additional custom policies can be added here
          EOT

          # Default policy for authenticated users
          "policy.default" = "role:readonly"

          # Scopes for RBAC
          scopes = "[groups, email]"
        }

        # Parameters
        params = {
          # Server configuration
          "server.insecure"                    = "true" # TLS terminated at ALB
          "server.basehref"                    = "/"
          "server.rootpath"                    = ""
          "server.disable.auth"                = "false"
          "server.enable.gzip"                 = "true"
          "server.x.frame.options"             = "sameorigin"
          "application.namespaces"             = local.argocd.namespace
          "applicationsetcontroller.enable.progressive.syncs" = "true"
        }
      }

      # Server configuration
      server = {
        # Resources
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }

        # Replicas for HA
        replicas = 2

        # Autoscaling
        autoscaling = {
          enabled     = true
          minReplicas = 2
          maxReplicas = 5
          targetCPUUtilizationPercentage    = 80
          targetMemoryUtilizationPercentage = 80
        }

        # Ingress configuration
        ingress = {
          enabled = true
          annotations = {
            # ALB configuration
            "kubernetes.io/ingress.class"                    = "alb"
            "alb.ingress.kubernetes.io/scheme"               = "internet-facing"
            "alb.ingress.kubernetes.io/target-type"          = "ip"
            "alb.ingress.kubernetes.io/backend-protocol"     = "HTTP"
            "alb.ingress.kubernetes.io/listen-ports"         = jsonencode([{ HTTPS = 443 }])
            "alb.ingress.kubernetes.io/certificate-arn"      = data.aws_acm_certificate.wildcard.arn
            "alb.ingress.kubernetes.io/ssl-redirect"         = "443"
            "alb.ingress.kubernetes.io/healthcheck-path"     = "/healthz"
            "alb.ingress.kubernetes.io/healthcheck-protocol" = "HTTP"
            "alb.ingress.kubernetes.io/success-codes"        = "200"

            # External DNS
            "external-dns.alpha.kubernetes.io/hostname" = local.subdomains.argocd

            # Security - dedicated ALB security group with HTTPS ingress
            "alb.ingress.kubernetes.io/security-groups" = aws_security_group.argocd_alb.id
          }

          hosts = [local.subdomains.argocd]

          tls = []
        }

        # Metrics
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = false
          }
        }
      }

      # Controller configuration
      controller = {
        resources = {
          requests = {
            cpu    = "250m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "1000m"
            memory = "1Gi"
          }
        }

        replicas = 1

        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = false
          }
        }
      }

      # Repo server configuration
      repoServer = {
        resources = {
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }

        replicas = 2

        autoscaling = {
          enabled     = true
          minReplicas = 2
          maxReplicas = 5
          targetCPUUtilizationPercentage    = 80
          targetMemoryUtilizationPercentage = 80
        }
      }

      # ApplicationSet controller
      applicationSet = {
        enabled = true
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }

      # Notifications controller
      notifications = {
        enabled = false
      }

      # Dex (OIDC proxy)
      dex = {
        enabled = true
        resources = {
          requests = {
            cpu    = "10m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }

      # Redis
      redis = {
        enabled = true
        resources = {
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
      }

      # Redis HA (disabled for dev)
      redis-ha = {
        enabled = false
      }
    })
  ]

  depends_on = [
    helm_release.aws_lb_controller,
    aws_cognito_user_pool_client.argocd
  ]
}
