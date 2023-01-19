tags             = { example = "eks_blueprint" }
fargate_profiles = []
managed_node_groups = [
  {
    name          = "default_managed"
    min_size      = 4
    max_size      = 6
    desired_size  = 4
    instance_type = "t3.medium"
  },
]
use_default_vpc = false
cidr            = "10.0.0.0/16"
private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
public_subnets  = ["10.0.4.0/24", "10.0.5.0/24"]
name            = "altech-dev"
aws_region      = "ap-southeast-1"
azs             = ["ap-southeast-1a", "ap-southeast-1b"]
