locals {
  karpenter_default_provisioner_files = [
    "${path.module}/default-provisioner.tmpl.yaml"
  ]
}

data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_iam_policy" "ssm_managed_instance" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "kubernetes_namespace" "namespace" {
  count = var.create_namespace ? 1 : 0
  metadata {
    name = var.karpenter_namespace
  }
}

module "iam_assumable_role_karpenter" {
  source                        = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version                       = "4.7.0"
  create_role                   = true
  role_name                     = "karpenter-controller-${var.cluster_name}"
  provider_url                  = data.aws_eks_cluster.cluster.identity.0.oidc.0.issuer
  oidc_fully_qualified_subjects = ["system:serviceaccount:karpenter:karpenter"]
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name = "karpenter-policy-${var.cluster_name}"
  role = module.iam_assumable_role_karpenter.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:RunInstances",
          "ec2:CreateTags",
          "iam:PassRole",
          "ec2:TerminateInstances",
          "ec2:DescribeLaunchTemplates",
          "ec2:DeleteLaunchTemplate",
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ssm:GetParameter"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_ec2_tag" "subnet_tags" {
  for_each = toset(var.private_subnet_ids)

  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.cluster_name}"
  value       = "owned"
}

resource "aws_ec2_tag" "karpenter_subnet_tags" {
  for_each = toset(var.private_subnet_ids)

  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

resource "aws_iam_role_policy_attachment" "karpenter_ssm_policy" {
  role       = var.cluster_worker_iam_role_name
  policy_arn = data.aws_iam_policy.ssm_managed_instance.arn
}

resource "aws_iam_instance_profile" "karpenter" {
  name = "KarpenterNodeInstanceProfile-${var.cluster_name}"
  role = var.cluster_worker_iam_role_name
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "https://charts.karpenter.sh"
  chart      = "karpenter"
  version    = var.karpenter_version
  namespace  = var.karpenter_namespace

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "clusterEndpoint"
    value = data.aws_eks_cluster.cluster.endpoint
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.iam_assumable_role_karpenter.iam_role_arn
  }

  set {
    name  = "aws.defaultInstanceProfile"
    value = "KarpenterNodeInstanceProfile-${var.cluster_name}"
  }

  values = [
    templatefile(
      "${path.module}/values.tmpl.yaml",
      {
        clusterName = var.cluster_name
      }
    )
  ]
}

resource "kubectl_manifest" "karpenter-provisioner-manifest" {
  for_each  = toset(coalescelist(var.karpenter_provisioner_files, local.karpenter_default_provisioner_files))
  yaml_body = templatefile(each.key, { cluster_name = var.cluster_name })

  depends_on = [
    helm_release.karpenter
  ]
}

