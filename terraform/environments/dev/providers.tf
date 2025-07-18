terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.83.0"
    }
  }

  backend "s3" {
    bucket = "nattapol-crc-dev-terraform"
    key    = "terraform.tfstate"
    region = "ap-southeast-7"
  }

  required_version = ">= 1.2.0"
}
