terraform {
  backend "s3" {
    bucket = "terraform-state-backend-20230109"
    key    = "cornerstone"
    region = "ap-east-1"
  }
}
