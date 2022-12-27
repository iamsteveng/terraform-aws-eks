output "kubeconfig" {
  description = "Bash script to update the kubeconfig file for the EKS cluster"
  value       = module.eks.kubeconfig
}

output "codebuild" {
  description = "Bash script to run the build projects using CodeBuild"
  value       = [for proj in values(module.ci) : proj.build]
}

output "features" {
  description = "Features configurations of the AWS EKS cluster"
  value       = module.eks.features
}

output "region" {
  description = "AWS region"
  value       = var.aws_region
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = local.cluster_name
}
