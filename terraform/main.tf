terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.83.0"
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
  region = "ap-southeast-7"
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

# DynamoDB

# TODO change the name to something better
locals {
  dynamodb_table_name = "nattapol-resume"
}

resource "aws_dynamodb_table" "visitor_counter" {
  name         = local.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "stats"
  attribute {
    name = "stats"
    type = "S"
  }
}

# Lambda

locals {
  lambda_function_name = "crc-visitor-counter"
  lambda_iam_role_name = "crc-visitor-counter-role"
  lambda_file_name     = "visitor_counter.zip"
  lambda_runtime       = "python3.13"
  lambda_handler       = "main.lambda_handler"
}
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_visitor_counter" {
  name               = local.lambda_iam_role_name
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy" "lambda_cloudwatch_logs" {
  name = "CloudWatchLog"
  role = aws_iam_role.lambda_visitor_counter.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.visitor_counter.arn
      },
    ]
  })
}

resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "DynamoDB"
  role = aws_iam_role.lambda_visitor_counter.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        "Effect" : "Allow",
        "Action" : "logs:CreateLogGroup",
        "Resource" : "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" : [
          "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.lambda_function_name}:*"
        ]
      }
    ]
  })
}

resource "aws_s3_bucket" "crc" {
  bucket = "nattapol-crc"
}

resource "aws_s3_bucket_versioning" "crc" {
  bucket = aws_s3_bucket.crc.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "visitor_counter" {
  bucket = aws_s3_bucket.crc.id
  key    = local.lambda_file_name
}

resource "aws_lambda_function" "visitor_counter" {
  function_name = local.lambda_function_name
  role          = aws_iam_role.lambda_visitor_counter.arn
  s3_bucket     = aws_s3_bucket.crc.id
  s3_key        = local.lambda_file_name
  runtime       = local.lambda_runtime
  handler       = local.lambda_handler
}
