data "aws_caller_identity" "current" {}

provider "kubernetes" {
  host                   = module.eks_cluster.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", local.workspace.eks_cluster.name,"--role-arn" ,"arn:aws:iam::${local.workspace.aws.account_id}:role/${local.workspace.aws.role}" ]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks_cluster.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = ["eks", "get-token", "--cluster-name", local.workspace.eks_cluster.name,"--role-arn" ,"arn:aws:iam::${local.workspace.aws.account_id}:role/${local.workspace.aws.role}" ]
    }
  }
}

module "eks_cluster" {
  source = "git::https://github.com/tothenew/terraform-aws-eks.git?ref=v0.0.1"
  # source = "../"
  cluster_name    = local.workspace.eks_cluster.name
  cluster_version = try(local.workspace.eks_cluster.version, "1.24")

  cluster_endpoint_private_access = try(local.workspace.eks_cluster.cluster_endpoint_private_access, false)
  cluster_endpoint_public_access  = try(local.workspace.eks_cluster.cluster_endpoint_public_access, true)

  vpc_id     = data.aws_vpc.selected.id
  subnet_ids = data.aws_subnets.private.ids

  # Self managed node groups will not automatically create the aws-auth configmap so we need to
  create_aws_auth_configmap = true
  manage_aws_auth_configmap = true
  create                    = true

  #Cluster Level Addons
  cluster_addons = local.workspace.eks_cluster.addons

  self_managed_node_group_defaults = {
    instance_type                          = "${local.workspace.eks_cluster.instance_type}"
    update_launch_template_default_version = true
    iam_role_additional_policies = [
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    ]
    metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = local.workspace.eks_cluster.http_token_option
        http_put_response_hop_limit = 2
  }
  }
  
  #Cluter Addition Security groups rules
  cluster_security_group_additional_rules =  {
      "cluster_rule_egress" = {
        "cidr_blocks" = [
          "10.1.0.0/16",
        ]
        "description" = "outbound vpc"
        "from_port" = 0
        "protocol" = "-1"
        "to_port" = 65535
        "type" = "egress"
      }
      "cluster_rule_ingress" = {
        "cidr_blocks" = [
          local.common.vpc_cidr,
        ]
        "description" = "inbound vpc"
        "from_port" = 0
        "protocol" = "tcp"
        "to_port" = 65535
        "type" = "ingress"
      }
    }

  self_managed_node_groups = {
    # Default node group - as provisioned by the module defaults
    default_node_group = {
      name = local.workspace.eks_cluster.name
      min_size     = try(local.workspace.eks_cluster.min_size, 2)
      desired_size = try(local.workspace.eks_cluster.min_size, 2)
      max_size     = try(local.workspace.eks_cluster.max_size, 5)
      tags = {
        "k8s.io/cluster-autoscaler/enabled" = "true"
        "k8s.io/cluster-autoscaler/${local.workspace.eks_cluster.name}" = "owned"


      }
      create_security_group          = true
      security_group_name            = local.workspace.eks_cluster.name
      security_group_use_name_prefix = true
      security_group_description     = "Self managed NodeGroup SG"
      security_group_rules = {
      "node_rules_egress" = {
        "cidr_blocks" = [
          "0.0.0.0/0",
        ]
        "description" = "outbound vpc"
        "from_port" = 0
        "protocol" = "-1"
        "to_port" = 65535
        "type" = "egress"
      }
      "node_rules_ingress" = {
        "cidr_blocks" = [
          local.common.vpc_cidr,
        ]
        "description" = "inbound vpc"
        "from_port" = 0
        "protocol" = "tcp"
        "to_port" = 65535
        "type" = "ingress"
      }
    }
}
  
    mixed = {
      name = local.workspace.eks_cluster.name
      min_size     = 0 #try(local.workspace.eks_cluster.min_size, 2)
      max_size     =  0 # try(local.workspace.eks_cluster.max_size, 5)
      desired_size = 0 #try(local.workspace.eks_cluster.min_size, 2)
      tags = {
        "k8s.io/cluster-autoscaler/enabled" = "true"
        "k8s.io/cluster-autoscaler/${local.workspace.eks_cluster.name}" = "owned"
      }

      #Node Security Group 
      create_security_group          = true
      security_group_name            = local.workspace.eks_cluster.name
      security_group_use_name_prefix = true
      security_group_description     = "Self managed NodeGroup SG"
      security_group_rules = {
      "node_rules_egress" = {
        "cidr_blocks" = [
          "0.0.0.0/0",
        ]
        "description" = "outbound vpc"
        "from_port" = 0
        "protocol" = "-1"
        "to_port" = 65535
        "type" = "egress"
      }
      "node_rules_ingress" = {
        "cidr_blocks" = [
          local.common.vpc_cidr,
        ]
        "description" = "inbound vpc"
        "from_port" = 0
        "protocol" = "tcp"
        "to_port" = 65535
        "type" = "ingress"
      }
    }


      pre_bootstrap_user_data = <<-EOT
        TOKEN=`curl -s  -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"`
        EC2_LIFE_CYCLE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN"  http://169.254.169.254/latest/meta-data/instance-life-cycle)
        INSTANCE_TYPE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN"  http://169.254.169.254/latest/meta-data/instance-type)
        AVAILABILITY_ZONE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN"  http://169.254.169.254/latest/meta-data/placement/availability-zone)
        EOT

      bootstrap_extra_args = "--kubelet-extra-args '--node-labels=node.kubernetes.io/lifecycle='\"$EC2_LIFE_CYCLE\"' --register-with-taints=instance_type='\"$INSTANCE_TYPE\"':NoSchedule,ec2_lifecycle='\"$EC2_LIFE_CYCLE\"':NoSchedule,availability_zone='\"$AVAILABILITY_ZONE\"':NoSchedule'"

      post_bootstrap_user_data = <<-EOT
        cd /tmp
        sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
        sudo systemctl enable amazon-ssm-agent
        sudo systemctl start amazon-ssm-agent
        EOT

     iam_role_additional_policies = [
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      ]
      block_device_mappings = {
  "xvda" = {
    "device_name" = "/dev/xvda"
    "ebs" = {
      "delete_on_termination" = true
      "encrypted" = true
      "iops" = 3000
      "throughput" = 150
      "volume_size" = 50
      "volume_type" = "gp3"
    }
  }
}
      use_mixed_instances_policy = "${local.workspace.eks_cluster.is_mixed_instance_policy}"
      mixed_instances_policy = {
        instances_distribution = "${local.workspace.eks_cluster.instances_distribution}"
        override = "${local.workspace.eks_cluster.override}"
      }
    }
  }
}

module "cluster_autoscaler" {
source = "git::https://github.com/tothenew/terraform-aws-eks.git//modules/terraform-aws-eks-cluster-autoscaler"
  enabled = true
  cluster_name                     = module.eks_cluster.cluster_id
  cluster_identity_oidc_issuer     = module.eks_cluster.cluster_oidc_issuer_url
  cluster_identity_oidc_issuer_arn = module.eks_cluster.oidc_provider_arn
  aws_region                       = local.workspace.aws.region
  depends_on = [
    module.eks_cluster
  ]
}

module "node_termination_handler" {
 source = "git::https://github.com/tothenew/terraform-aws-eks.git//modules/terraform-aws-eks-node-termination-handler"
}


module "helm_iam_policy" {
  source  = "git::https://github.com/terraform-aws-modules/terraform-aws-iam.git//modules/iam-policy"

  name        = "${local.workspace.eks_cluster.name}-shared-apps-helm-integration-policy"
  path        = "/"
  description = "Policy for EKS load-balancer-controller"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "secretsmanager:DescribeSecret",
                "secretsmanager:GetSecretValue",
                "ssm:DescribeParameters",
                "ssm:GetParameter",
                "ssm:GetParameters",
                "ssm:GetParametersByPath"
            ],
            "Effect": "Allow",
            "Resource": "*"
        },
        {
            "Action": [
                "kms:DescribeCustomKeyStores",
                "kms:ListKeys",
                "kms:ListAliases"
            ],
            "Effect": "Allow",
            "Resource": "*"
        },
        {
            "Action": [
                "kms:Decrypt",
                "kms:GetKeyRotationStatus",
                "kms:GetKeyPolicy",
                "kms:DescribeKey"
            ],
            "Effect": "Allow",
            "Resource": "*"
        }
    ]
}
    
EOF
}

// load balancer controller
module "load_balancer_controller" {
  source = "git::https://github.com/tothenew/terraform-aws-eks.git//modules/terraform-aws-eks-lb-controller"

  cluster_identity_oidc_issuer     = module.eks_cluster.cluster_oidc_issuer_url
  cluster_identity_oidc_issuer_arn = module.eks_cluster.oidc_provider_arn
  cluster_name                     = module.eks_cluster.cluster_id
  depends_on = [
    module.eks_cluster
  ]
}

module "secrets-store-csi" {
  depends_on = [
    module.eks_cluster
  ]
  source = "git::https://github.com/tothenew/terraform-aws-eks.git//modules/secret-store-csi"
  cluster_name = module.eks_cluster.cluster_id
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  chart_version = local.workspace.eks_cluster.secrets-store-csi.chart_version
  ascp_chart_version = local.workspace.eks_cluster.secrets-store-csi.ascp_chart_version
  syncSecretEnabled = local.workspace.eks_cluster.secrets-store-csi.syncSecretEnabled
  enableSecretRotation = local.workspace.eks_cluster.secrets-store-csi.enableSecretRotation
  namespace_service_accounts = ["${local.workspace.environment_name}:user-service-app-service-role","${local.workspace.environment_name}:nginx-app-service-role"]
}
resource "aws_iam_role_policy_attachment" "secrets_integration_policy_attachment" {
  depends_on = [
    module.secrets-store-csi
  ]
  count = 1
  role       = module.secrets-store-csi.iam_role_name
  policy_arn = module.helm_iam_policy.arn
}
