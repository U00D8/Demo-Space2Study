terraform {
  backend "s3" {
    bucket         = "space2study-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "eu-north-1"
    encrypt        = true
    dynamodb_table = "space2study-terraform-locks"
  }
}