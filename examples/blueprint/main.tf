### EKS Blueprint

terraform {
  required_version = "~> 1.0"
}

provider "aws" {
  region = var.aws_region
}

provider "helm" {
  kubernetes {
    host                   = module.eks.kubeauth.host
    token                  = module.eks.kubeauth.token
    cluster_ca_certificate = module.eks.kubeauth.ca
  }
}

locals {
  cluster_name = "${var.name}-eks-${random_string.suffix.result}"
}

### vpc
module "vpc" {
  source  = "Young-ook/vpc/aws"
  version = "1.0.3"
  name    = var.name
  tags    = var.tags
  vpc_config = var.use_default_vpc ? null : {
    azs             = var.azs
    cidr            = var.cidr
    private_subnets = var.private_subnets
    public_subnets  = var.public_subnets

    enable_nat_gateway   = true
    single_nat_gateway   = true
    enable_dns_hostnames = true

    public_subnet_tags = {
      "kubernetes.io/cluster/${local.cluster_name}" = "shared"
      "kubernetes.io/role/elb"                      = 1
    }

    private_subnet_tags = {
      "kubernetes.io/cluster/${local.cluster_name}" = "shared"
      "kubernetes.io/role/internal-elb"             = 1
    }
  }

  # Amazon ECS tasks using the Fargate launch type and platform version 1.3.0 or earlier only require
  # the com.amazonaws.region.ecr.dkr Amazon ECR VPC endpoint and the Amazon S3 gateway endpoints.
  #
  # Amazon ECS tasks using the Fargate launch type and platform version 1.4.0 or later require both
  # the com.amazonaws.region.ecr.dkr and com.amazonaws.region.ecr.api Amazon ECR VPC endpoints and
  # the Amazon S3 gateway endpoints.
  #
  # For more details, please visit the https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html
  vpce_config = [
    {
      service             = "ecr.dkr"
      type                = "Interface"
      private_dns_enabled = false
    },
    {
      service             = "ecr.api"
      type                = "Interface"
      private_dns_enabled = true
    },
    # For more details, please refer to this web page, https://aws.amazon.com/about-aws/whats-new/2022/12/amazon-eks-supports-aws-privatelink/
    {
      service             = "eks"
      type                = "Interface"
      private_dns_enabled = true
    },
    {
      service = "s3"
      type    = "Gateway"
    },
  ]
}

### eks cluster
module "eks" {
  source              = "Young-ook/eks/aws"
  version             = "2.0.0"
  name                = local.cluster_name
  tags                = var.tags
  subnets             = values(module.vpc.subnets[var.use_default_vpc ? "public" : "private"])
  enable_ssm          = var.enable_ssm
  kubernetes_version  = var.kubernetes_version
  fargate_profiles    = (var.use_default_vpc ? [] : var.fargate_profiles)
  managed_node_groups = var.managed_node_groups
  node_groups         = var.node_groups
}

### aws partitions
module "aws" {
  source = "Young-ook/spinnaker/aws//modules/aws-partitions"
}

### eks-addons
module "eks-addons" {
  source  = "Young-ook/eks/aws//modules/eks-addons"
  version = "2.0.3"
  tags    = var.tags
  addons = [
    {
      name     = "vpc-cni"
      eks_name = module.eks.cluster.name
    },
    {
      name     = "coredns"
      eks_name = module.eks.cluster.name
    },
    {
      name     = "kube-proxy"
      eks_name = module.eks.cluster.name
    },
    {
      name           = "aws-ebs-csi-driver"
      namespace      = "kube-system"
      serviceaccount = "ebs-csi-controller-sa"
      eks_name       = module.eks.cluster.name
      oidc           = module.eks.oidc
      policy_arns = [
        format("arn:%s:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy", module.aws.partition.partition),
      ]
    },
  ]
}

### helm-addons
module "helm-addons" {
  depends_on = [module.eks-addons]
  source     = "Young-ook/eks/aws//modules/helm-addons"
  version    = "2.0.0"
  tags       = var.tags
  addons = [
    {
      repository     = "https://aws.github.io/eks-charts"
      name           = "appmesh-controller"
      chart_name     = "appmesh-controller"
      namespace      = "kube-system"
      serviceaccount = "appmesh-controller"
      values = {
        "region"           = var.aws_region
        "tracing.enabled"  = true
        "tracing.provider" = "x-ray"
      }
      oidc = module.eks.oidc
      policy_arns = [
        format("arn:%s:iam::aws:policy/AWSAppMeshEnvoyAccess", module.aws.partition.partition),
        format("arn:%s:iam::aws:policy/AWSCloudMapFullAccess", module.aws.partition.partition),
        format("arn:%s:iam::aws:policy/AWSXRayDaemonWriteAccess", module.aws.partition.partition),
      ]
    },
    {
      repository     = "https://aws.github.io/eks-charts"
      name           = "aws-cloudwatch-metrics"
      chart_name     = "aws-cloudwatch-metrics"
      namespace      = "kube-system"
      serviceaccount = "aws-cloudwatch-metrics"
      values = {
        "clusterName" = module.eks.cluster.name
      }
      oidc = module.eks.oidc
      policy_arns = [
        format("arn:%s:iam::aws:policy/CloudWatchAgentServerPolicy", module.aws.partition.partition)
      ]
    },
    {
      repository     = "https://aws.github.io/eks-charts"
      name           = "aws-for-fluent-bit"
      chart_name     = "aws-for-fluent-bit"
      namespace      = "kube-system"
      serviceaccount = "aws-for-fluent-bit"
      values = {
        "cloudWatch.enabled"      = true
        "cloudWatch.region"       = var.aws_region
        "cloudWatch.logGroupName" = format("/aws/containerinsights/%s/application", module.eks.cluster.name)
        "firehose.enabled"        = false
        "kinesis.enabled"         = false
        "elasticsearch.enabled"   = false
      }
      oidc = module.eks.oidc
      policy_arns = [
        format("arn:%s:iam::aws:policy/CloudWatchAgentServerPolicy", module.aws.partition.partition)
      ]
    },
    {
      repository     = "https://aws.github.io/eks-charts"
      name           = "aws-load-balancer-controller"
      chart_name     = "aws-load-balancer-controller"
      namespace      = "kube-system"
      serviceaccount = "aws-load-balancer-controller"
      values = module.eks.features.fargate_enabled ? {
        "vpcId"       = module.vpc.vpc.id
        "clusterName" = module.eks.cluster.name
        } : {
        "clusterName" = module.eks.cluster.name
      }
      oidc        = module.eks.oidc
      policy_arns = [aws_iam_policy.lbc.arn]
    },
    # {
    #   repository     = "https://charts.karpenter.sh"
    #   name           = "karpenter"
    #   chart_name     = "karpenter"
    #   namespace      = "kube-system"
    #   serviceaccount = "karpenter"
    #   values = {
    #     "clusterName"                = module.eks.cluster.name
    #     "clusterEndpoint"            = module.eks.cluster.control_plane.endpoint
    #     "aws.defaultInstanceProfile" = module.eks.instance_profile.node_groups == null ? module.eks.instance_profile.managed_node_groups.arn : module.eks.instance_profile.node_groups.arn
    #   }
    #   oidc        = module.eks.oidc
    #   policy_arns = [aws_iam_policy.kpt.arn]
    # },
    # {
    #   repository     = "${path.module}/charts/"
    #   name           = "cluster-autoscaler"
    #   chart_name     = "cluster-autoscaler"
    #   namespace      = "kube-system"
    #   serviceaccount = "cluster-autoscaler"
    #   values = {
    #     "awsRegion"                 = var.aws_region
    #     "autoDiscovery.clusterName" = module.eks.cluster.name
    #   }
    #   oidc        = module.eks.oidc
    #   policy_arns = [aws_iam_policy.cas.arn]
    # },
    {
      repository     = "https://kubernetes-sigs.github.io/metrics-server/"
      name           = "metrics-server"
      chart_name     = "metrics-server"
      namespace      = "kube-system"
      serviceaccount = "metrics-server"
      values = {
        "args[0]" = "--kubelet-preferred-address-types=InternalIP"
      }
    },
    {
      repository     = "https://aws.github.io/eks-charts"
      name           = "aws-node-termination-handler"
      chart_name     = "aws-node-termination-handler"
      namespace      = "kube-system"
      serviceaccount = "aws-node-termination-handler"
    },
  ]
}

resource "aws_iam_policy" "lbc" {
  name        = "aws-loadbalancer-controller"
  tags        = merge({ "terraform.io" = "managed" }, var.tags)
  description = format("Allow aws-load-balancer-controller to manage AWS resources")
  policy      = file("${path.module}/policy.aws-loadbalancer-controller.json")
}

resource "aws_iam_policy" "kpt" {
  name        = "karpenter"
  tags        = merge({ "terraform.io" = "managed" }, var.tags)
  description = format("Allow karpenter to manage AWS resources")
  policy      = file("${path.module}/policy.karpenter.json")
}

resource "aws_iam_policy" "cas" {
  name        = "cluster-autoscaler"
  tags        = merge({ "terraform.io" = "managed" }, var.tags)
  description = format("Allow cluster-autoscaler to manage AWS resources")
  policy      = file("${path.module}/policy.cluster-autoscaler.json")
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}
