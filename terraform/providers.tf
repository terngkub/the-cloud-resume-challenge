terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.83.0"
    }
    random = {
        source = "hashicorp/random"
        version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket = "nattapol-crc-prod-terraform"
    key    = "terraform.tfstate"
    region = "ap-southeast-7"
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "ap-southeast-7"
}

# Imported certificate has to be in us-east-1 for CloudFront
provider "aws" {
  region = "us-east-1"
  alias  = "us-east-1"
}