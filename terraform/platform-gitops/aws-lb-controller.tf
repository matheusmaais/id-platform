################################################################################
# AWS Load Balancer Controller IAM Role (IRSA)
################################################################################

data "aws_iam_policy_document" "aws_lb_controller_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.eks.outputs.oidc_provider_arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "${replace(data.terraform_remote_state.eks.outputs.oidc_provider, "https://", "")}:sub"
      values   = ["system:serviceaccount:${local.aws_lb_controller.namespace}:${local.aws_lb_controller.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(data.terraform_remote_state.eks.outputs.oidc_provider, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "aws_lb_controller" {
  name               = "${var.cluster_name}-aws-lb-controller"
  assume_role_policy = data.aws_iam_policy_document.aws_lb_controller_assume_role.json

  tags = merge(
    local.common_tags,
    {
      Name = "${var.cluster_name}-aws-lb-controller"
    }
  )
}

# AWS Load Balancer Controller IAM Policy
# Using AWS-managed policy (recommended approach)
resource "aws_iam_role_policy_attachment" "aws_lb_controller" {
  role       = aws_iam_role.aws_lb_controller.name
  policy_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:policy/AWSLoadBalancerControllerIAMPolicy"
}

################################################################################
# AWS Load Balancer Controller Helm Release
################################################################################

resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = local.aws_lb_controller.chart_version
  namespace  = local.aws_lb_controller.namespace

  values = [
    yamlencode({
      clusterName = data.aws_eks_cluster.main.name
      region      = data.aws_region.current.name
      vpcId       = data.terraform_remote_state.vpc.outputs.vpc_id

      serviceAccount = {
        create = true
        name   = local.aws_lb_controller.service_account
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.aws_lb_controller.arn
        }
      }

      # Resources
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

      # Enable controller features
      enableCertManager = false
      enableShield      = false
      enableWaf         = false
      enableWafv2       = false

      # Logging
      logLevel = "info"

      # Replica count
      replicaCount = 2

      # Pod disruption budget
      podDisruptionBudget = {
        maxUnavailable = 1
      }

      # Topology spread constraints for HA
      topologySpreadConstraints = [
        {
          maxSkew           = 1
          topologyKey       = "topology.kubernetes.io/zone"
          whenUnsatisfiable = "ScheduleAnyway"
          labelSelector = {
            matchLabels = {
              "app.kubernetes.io/name"     = "aws-load-balancer-controller"
              "app.kubernetes.io/instance" = "aws-load-balancer-controller"
            }
          }
        }
      ]
    })
  ]

  depends_on = [
    aws_iam_role_policy_attachment.aws_lb_controller
  ]
}
