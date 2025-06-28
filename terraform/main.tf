terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  backend "s3" {
    bucket = "nattapol-cloud-resume-challenge-terraform"
    key    = "terraform.tfstate"
    region = "ap-southeast-7"
  }

  required_version = ">= 1.2.0"
}


# Providers

provider "aws" {
  region                 = "ap-southeast-7"
  skip_region_validation = true
}

# Imported certificate has to be in us-east-1 for CloudFront
provider "aws" {
  region = "us-east-1"
  alias  = "us-east-1"
}

# S3

resource "aws_s3_bucket" "resume_website" {
  bucket = "resume.nattapol.com"
}

resource "aws_s3_bucket_versioning" "resume_website" {
  bucket = aws_s3_bucket.resume_website.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_website_configuration" "resume_website" {
  bucket = aws_s3_bucket.resume_website.id

  index_document {
    suffix = "resume.html"
  }
}

# CloudFront

locals {
  website_domain = "resume.nattapol.com"
  root_object    = "resume.html"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_acm_certificate" "resume_website" {
  provider = aws.us-east-1
  domain   = "nattapol.com"
}

resource "aws_cloudfront_origin_access_control" "resume_website" {
  name                              = local.website_domain
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "resume_website" {
  origin {
    domain_name              = aws_s3_bucket.resume_website.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.resume_website.id
    origin_id                = local.website_domain
  }

  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  default_root_object = local.root_object
  aliases             = [local.website_domain]

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = local.website_domain
    viewer_protocol_policy = "allow-all"
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn            = data.aws_acm_certificate.resume_website.arn
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }

  tags = {
    "Name" = local.website_domain
  }
  tags_all = {
    "Name" = local.website_domain
  }
}
