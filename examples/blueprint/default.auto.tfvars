tags             = { example = "eks_blueprint" }
fargate_profiles = []
managed_node_groups = [
  {
    name          = "default"
    min_size      = 1
    max_size      = 5
    desired_size  = 3
    instance_type = "t3.medium"
  },
]
node_groups = [
  {
    name          = "default"
    min_size      = 1
    max_size      = 5
    desired_size  = 3
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
