locals {
  aws_partition = "aws"
  account_id    = data.aws_caller_identity.current.account_id
  region        = data.aws_region.current.name
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

/**
 * Can only be used in us-east-1:
 * registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ecrpublic_authorization_token
 */
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.use1
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
  oidc_fully_qualified_subjects = ["system:serviceaccount:${var.karpenter_namespace}:karpenter"]
}

# Updated for v0.33.0+ and v1beta1 APIs
resource "aws_iam_role_policy" "karpenter_controller" {
  name = "karpenter-policy-${var.cluster_name}"
  role = module.iam_assumable_role_karpenter.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowScopedEC2InstanceActions",
        Effect = "Allow",
        Resource = [
          "arn:${local.aws_partition}:ec2:${local.region}::image/*",
          "arn:${local.aws_partition}:ec2:${local.region}::snapshot/*",
          "arn:${local.aws_partition}:ec2:${local.region}:*:security-group/*",
          "arn:${local.aws_partition}:ec2:${local.region}:*:subnet/*",
          "arn:${local.aws_partition}:ec2:${local.region}:*:launch-template/*"
        ],
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet"
        ]
      },
      {
        Sid    = "AllowScopedEC2InstanceActionsWithTags",
        Effect = "Allow",
        Resource = [
          "arn:${local.aws_partition}:ec2:${local.region}:*:fleet/*",
          "arn:${local.aws_partition}:ec2:${local.region}:*:instance/*",
          "arn:${local.aws_partition}:ec2:${local.region}:*:volume/*",
          "arn:${local.aws_partition}:ec2:${local.region}:*:network-interface/*",
          "arn:${local.aws_partition}:ec2:${local.region}:*:launch-template/*",
          "arn:${local.aws_partition}:ec2:${local.region}:*:spot-instances-request/*"
        ],
        Action = [
          "ec2:RunInstances",
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate"
        ],
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          },
          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid    = "AllowScopedResourceCreationTagging",
        Effect = "Allow",
        Resource = [
          "arn:${local.aws_partition}:ec2:${local.region}:*:fleet/*",
          "arn:${local.aws_partition}:ec2:${local.region}:*:instance/*",
          "arn:${local.aws_partition}:ec2:${local.region}:*:volume/*",
          "arn:${local.aws_partition}:ec2:${local.region}:*:network-interface/*",
          "arn:${local.aws_partition}:ec2:${local.region}:*:launch-template/*",
          "arn:${local.aws_partition}:ec2:${local.region}:*:spot-instances-request/*"
        ],
        Action = "ec2:CreateTags",
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned",
            "ec2:CreateAction" = [
              "RunInstances",
              "CreateFleet",
              "CreateLaunchTemplate"
            ]
          },
          StringLike = {
            "aws:RequestTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid      = "AllowScopedResourceTagging",
        Effect   = "Allow",
        Resource = "arn:${local.aws_partition}:ec2:${local.region}:*:instance/*",
        Action   = "ec2:CreateTags",
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          },
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          },
          "ForAllValues:StringEquals" = {
            "aws:TagKeys" = [
              "karpenter.sh/nodeclaim",
              "Name"
            ]
          }
        }
      },
      {
        Sid    = "AllowScopedDeletion",
        Effect = "Allow",
        Resource = [
          "arn:${local.aws_partition}:ec2:${local.region}:*:instance/*",
          "arn:${local.aws_partition}:ec2:${local.region}:*:launch-template/*"
        ],
        Action = [
          "ec2:TerminateInstances",
          "ec2:DeleteLaunchTemplate"
        ],
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned"
          },
          StringLike = {
            "aws:ResourceTag/karpenter.sh/nodepool" = "*"
          }
        }
      },
      {
        Sid      = "AllowRegionalReadActions",
        Effect   = "Allow",
        Resource = "*",
        Action = [
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets"
        ],
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = "${local.region}"
          }
        }
      },
      {
        Sid      = "AllowSSMReadActions",
        Effect   = "Allow",
        Resource = "arn:${local.aws_partition}:ssm:${local.region}::parameter/aws/service/*",
        Action   = "ssm:GetParameter"
      },
      {
        Sid      = "AllowPricingReadActions",
        Effect   = "Allow",
        Resource = "*",
        Action   = "pricing:GetProducts"
      },
      {
        Sid      = "AllowInterruptionQueueActions",
        Effect   = "Allow",
        Resource = "arn:aws:sqs:${local.region}:${local.account_id}:${var.cluster_name}",
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage",
        ]
      },
      {
        Sid      = "AllowPassingInstanceRole",
        Effect   = "Allow",
        Resource = "arn:${local.aws_partition}:iam::${local.account_id}:role/${var.iam_role_name}",
        Action   = "iam:PassRole",
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileCreationActions",
        Effect   = "Allow",
        Resource = "*",
        Action   = "iam:CreateInstanceProfile",
        Condition = {
          StringEquals = {
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}" = "owned",
            "aws:RequestTag/topology.kubernetes.io/region"             = "${local.region}"
          },
          StringLike = {
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileTagActions",
        Effect   = "Allow",
        Resource = "*",
        Action   = "iam:TagInstanceProfile",
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned",
            "aws:ResourceTag/topology.kubernetes.io/region"             = "${local.region}",
            "aws:RequestTag/kubernetes.io/cluster/${var.cluster_name}"  = "owned",
            "aws:RequestTag/topology.kubernetes.io/region"              = "${local.region}"
          },
          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*",
            "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"  = "*"
          }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileActions",
        Effect   = "Allow",
        Resource = "*",
        Action = [
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile"
        ],
        Condition = {
          StringEquals = {
            "aws:ResourceTag/kubernetes.io/cluster/${var.cluster_name}" = "owned",
            "aws:ResourceTag/topology.kubernetes.io/region"             = "${local.region}"
          },
          StringLike = {
            "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*"
          }
        }
      },
      {
        Sid      = "AllowInstanceProfileReadActions",
        Effect   = "Allow",
        Resource = "*",
        Action   = "iam:GetInstanceProfile"
      },
      {
        Sid      = "AllowAPIServerEndpointDiscovery",
        Effect   = "Allow",
        Resource = "arn:${local.aws_partition}:eks:${local.region}:${local.account_id}:cluster/${var.cluster_name}",
        Action   = "eks:DescribeCluster"
      }
    ]
  })
}

resource "helm_release" "karpenter-crd" {
  name                = "karpenter-crd"
  repository          = "oci://public.ecr.aws/karpenter"
  chart               = "karpenter-crd"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  version             = var.karpenter_version
  namespace           = var.karpenter_namespace
}

resource "helm_release" "karpenter" {
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  chart               = "karpenter"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password
  version             = var.karpenter_version
  namespace           = var.karpenter_namespace

  set {
    name  = "settings.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "settings.clusterEndpoint"
    value = data.aws_eks_cluster.cluster.endpoint
  }

  # To be enabled when we want to migrate away from aws-node-termination-handler
  set {
    name  = "settings.interruptionQueue"
    value = var.cluster_name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.iam_assumable_role_karpenter.iam_role_arn
  }

  values = [
    templatefile(
      "${path.module}/values.tmpl.yaml",
      {
        clusterName  = var.cluster_name
        num_replicas = var.karpenter_number_of_replicas
        log_level    = var.log_level
      }
    )
  ]

  depends_on = [
    helm_release.karpenter-crd
  ]
}

resource "kubectl_manifest" "karpenter-provisioner-manifest" {
  for_each = var.karpenter_nodepools
  yaml_body = templatefile(each.key, merge({
    cluster_name       = var.cluster_name
    availability_zones = var.availability_zones
    iam_role_name      = var.iam_role_name
  }, var.additional_nodepool_parameters))

  depends_on = [
    helm_release.karpenter
  ]
}

