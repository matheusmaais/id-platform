################################################################################
# External-DNS IAM Role (IRSA)
################################################################################

data "aws_iam_policy_document" "external_dns_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.eks.outputs.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values   = ["system:serviceaccount:${local.external_dns.namespace}:${local.external_dns.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_dns" {
  name               = "${local.cluster_name}-external-dns"
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume_role.json

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-external-dns"
    }
  )
}

# External-DNS IAM Policy (scoped to hosted zone)
data "aws_iam_policy_document" "external_dns" {
  statement {
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets"
    ]
    resources = [
      "arn:aws:route53:::hostedzone/${data.aws_route53_zone.main.zone_id}"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "external_dns" {
  name        = "${local.cluster_name}-external-dns"
  description = "IAM policy for External-DNS to manage Route53 records"
  policy      = data.aws_iam_policy_document.external_dns.json

  tags = merge(
    local.common_tags,
    {
      Name = "${local.cluster_name}-external-dns"
    }
  )
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}

################################################################################
# External-DNS Helm Release
################################################################################

resource "helm_release" "external_dns" {
  name             = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  version          = local.external_dns.chart_version
  namespace        = local.external_dns.namespace
  create_namespace = true

  values = [
    yamlencode({
      # Provider configuration
      provider = {
        name = "aws"
      }

      # AWS-specific configuration
      aws = {
        region          = data.aws_region.current.name
        zoneType        = "public"
        assumeRoleArn   = "" # Using IRSA instead
        batchChangeSize = 1000
      }

      # Sources - what resources to watch
      sources = [
        "ingress",
        "service"
      ]

      # Domain filters
      domainFilters = [local.domain]

      # Zone ID filters (more specific)
      zoneIdFilters = [data.aws_route53_zone.main.zone_id]

      # Policy
      policy = local.external_dns.policy # upsert-only

      # Registry configuration
      registry   = "txt"
      txtOwnerId = local.external_dns.txt_owner_id
      txtPrefix  = "external-dns-"

      # Service account with IRSA
      serviceAccount = {
        create = true
        name   = local.external_dns.service_account
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns.arn
        }
      }

      # Resources
      resources = {
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
      }

      # Logging
      logLevel  = "info"
      logFormat = "json"

      # Sync interval
      interval = "1m"

      # Trigger loop on events
      triggerLoopOnEvent = true

      # Pod security context
      podSecurityContext = {
        fsGroup      = 65534
        runAsNonRoot = true
        runAsUser    = 65534
      }

      securityContext = {
        allowPrivilegeEscalation = false
        readOnlyRootFilesystem   = true
        runAsNonRoot             = true
        runAsUser                = 65534
        capabilities = {
          drop = ["ALL"]
        }
      }

      # Metrics
      metrics = {
        enabled = true
        port    = 7979
      }
    })
  ]

  depends_on = [
    aws_iam_role_policy_attachment.external_dns,
    helm_release.aws_lb_controller
  ]
}
