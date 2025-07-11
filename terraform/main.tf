# S3

resource "aws_s3_bucket" "resume_website" {
  bucket = var.full_domain_name
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
    suffix = var.website_index_file
  }
}

# CloudFront

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_acm_certificate" "resume_website" {
  provider = aws.us-east-1
  domain   = var.root_domain_name
}

resource "aws_cloudfront_origin_access_control" "resume_website" {
  name                              = var.full_domain_name
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "resume_website" {
  origin {
    domain_name              = aws_s3_bucket.resume_website.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.resume_website.id
    origin_id                = var.full_domain_name
  }

  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  default_root_object = var.website_index_file
  aliases             = [var.full_domain_name]

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = var.full_domain_name
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
    "Name" = var.full_domain_name
  }
  tags_all = {
    "Name" = var.full_domain_name
  }
}

# Naming

resource "random_id" "resource_suffix" {
  byte_length = 4
  keepers = {
    env = var.environment
    project = var.project_name
  }
}

locals {
  prefix = "${var.project_name}-${var.environment}"
  suffix = random_id.resource_suffix.hex
  dynamodb_table_name = "${local.prefix}-visitor-counter-${local.suffix}"
  lambda_function_name = "${local.prefix}-visitor-counter-${local.suffix}" 
  lambda_iam_role_name =  "${local.prefix}-visitor-counter-role-${local.suffix}"
  api_gateway_name =  "${local.prefix}-visitor-counter-${local.suffix}"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}


# DynamoDB

resource "aws_dynamodb_table" "visitor_counter" {
  name         = local.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "stats"
  attribute {
    name = "stats"
    type = "S"
  }
}

resource "aws_dynamodb_table_item" "visitor_counter" {
  table_name = aws_dynamodb_table.visitor_counter.name
  hash_key = aws_dynamodb_table.visitor_counter.hash_key
  item = <<ITEM
  {
    "stats": {"S": "visitor-counter"},
    "count": {"N": "0"}
  }
  ITEM
}

# Lambda

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

# TODO do I really need this?
resource "aws_s3_object" "visitor_counter" {
  bucket = aws_s3_bucket.crc.id
  key    = var.lambda_file_name
}

resource "aws_lambda_function" "visitor_counter" {
  function_name = local.lambda_function_name
  role          = aws_iam_role.lambda_visitor_counter.arn
  s3_bucket     = aws_s3_bucket.crc.id
  s3_key        = var.lambda_file_name
  runtime       = var.lambda_runtime
  handler       = var.lambda_handler

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.visitor_counter.name
    }
  }
}

# API Gateway

locals {
  api_allow_origin = "https://${var.full_domain_name}"
}

resource "aws_api_gateway_rest_api" "visitor_counter" {
  name = local.api_gateway_name

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "visitor_counter" {
  rest_api_id = aws_api_gateway_rest_api.visitor_counter.id
  parent_id   = aws_api_gateway_rest_api.visitor_counter.root_resource_id
  path_part   = var.api_path
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
    "method.response.header.Access-Control-Allow-Origin"  = "'${local.api_allow_origin}'"
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
