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

# API Gateway

locals {
  api_path         = "increase-visitor-counter"
  api_allow_origin = "https://resume.nattapol.com"
}

resource "aws_api_gateway_rest_api" "visitor_counter" {
  name = "crc-visitor-counter"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "visitor_counter" {
  rest_api_id = aws_api_gateway_rest_api.visitor_counter.id
  parent_id   = aws_api_gateway_rest_api.visitor_counter.root_resource_id
  path_part   = local.api_path
}

moved {
  from = aws_api_gateway_method.visitor_counter
  to   = aws_api_gateway_method.visitor_counter_post
}

moved {
  from = aws_api_gateway_integration.visitor_counter
  to   = aws_api_gateway_integration.visitor_counter_post
}

resource "aws_api_gateway_method" "visitor_counter_post" {
  rest_api_id   = aws_api_gateway_rest_api.visitor_counter.id
  resource_id   = aws_api_gateway_resource.visitor_counter.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "visitor_counter_post" {
  rest_api_id             = aws_api_gateway_rest_api.visitor_counter.id
  resource_id             = aws_api_gateway_resource.visitor_counter.id
  http_method             = aws_api_gateway_method.visitor_counter_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.visitor_counter.invoke_arn
}

# Allow API Gateway to invoke the Lambda function
resource "aws_lambda_permission" "visitor_count_post" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.visitor_counter.execution_arn}/*"
}

## CORS

resource "aws_api_gateway_method" "visitor_counter_options" {
  rest_api_id   = aws_api_gateway_rest_api.visitor_counter.id
  resource_id   = aws_api_gateway_resource.visitor_counter.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "visitor_counter_options" {
  rest_api_id = aws_api_gateway_rest_api.visitor_counter.id
  resource_id = aws_api_gateway_resource.visitor_counter.id
  http_method = aws_api_gateway_method.visitor_counter_options.http_method
  type        = "MOCK"
}

resource "aws_api_gateway_integration_response" "visitor_counter_options" {
  depends_on = [
    aws_api_gateway_integration.visitor_counter_options,
    aws_api_gateway_method_response.visitor_counter_options
  ]

  rest_api_id = aws_api_gateway_rest_api.visitor_counter.id
  resource_id = aws_api_gateway_resource.visitor_counter.id
  http_method = aws_api_gateway_method.visitor_counter_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,POST'"
    "method.response.header.Access-Control-Allow-Origin"  = "'https://resume.nattapol.com'"
  }
}

resource "aws_api_gateway_method_response" "visitor_counter_options" {
  rest_api_id = aws_api_gateway_rest_api.visitor_counter.id
  resource_id = aws_api_gateway_resource.visitor_counter.id
  http_method = aws_api_gateway_method.visitor_counter_options.http_method
  status_code = "200"

  # TODO why empty?
  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

## Deployment

resource "aws_api_gateway_deployment" "visitor_counter" {
  rest_api_id = aws_api_gateway_rest_api.visitor_counter.id
}

resource "aws_api_gateway_stage" "visitor_counter_prod" {
  rest_api_id   = aws_api_gateway_rest_api.visitor_counter.id
  deployment_id = aws_api_gateway_deployment.visitor_counter.id
  stage_name    = "prod"
}
