terraform {
  backend "s3" {
    bucket = "terraform-state-backend-20230108"
    key    = "cornerstone"
    region = "ap-southeast-1"
  }
}
