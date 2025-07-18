provider "aws" {
  region = "ap-southeast-7"
}

# Imported certificate has to be in us-east-1 for CloudFront
provider "aws" {
  region = "us-east-1"
  alias  = "us-east-1"
}