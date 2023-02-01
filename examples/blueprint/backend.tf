terraform {
  backend "s3" {
    bucket = "terraform-state-backend-20230131"
    key    = "cornerstone-prod"
    region = "ap-east-1"
  }
}
