################################################################################
# Naming and Metadata
################################################################################

locals {
  backend_name = "${var.project_name}-${var.environment}-visitor-counter"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}


################################################################################
# DynamoDB
################################################################################

resource "aws_dynamodb_table" "visitor_counter" {
  name         = local.backend_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "stats"
  attribute {
    name = "stats"
    type = "S"
  }
}

# Populate the table on the creation
resource "aws_dynamodb_table_item" "visitor_counter" {
  table_name = aws_dynamodb_table.visitor_counter.name
  hash_key = aws_dynamodb_table.visitor_counter.hash_key
  item = <<ITEM
  {
    "stats": {"S": "visitor-counter"},
    "count": {"N": "0"}
  }
  ITEM

  # Ignore any changes on the item afterward
  lifecycle {
    ignore_changes = [item]
  }
}


################################################################################
# Lambda
################################################################################

resource "aws_lambda_function" "visitor_counter" {
  depends_on = [  ]
  function_name = local.backend_name
  role          = aws_iam_role.lambda_visitor_counter.arn
  s3_bucket     = aws_s3_bucket.crc.id
  s3_key        = var.lambda_file_name
  runtime       = var.lambda_runtime
  handler       = var.lambda_handler

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.visitor_counter.name
      FULL_DOMAIN_NAME = var.full_domain_name
    }
  }
}


# Code
################################################################################

resource "aws_s3_bucket" "crc" {
  bucket = var.lambda_s3_bucket_name
}

resource "aws_s3_bucket_versioning" "crc" {
  bucket = aws_s3_bucket.crc.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_object" "visitor_counter" {
  bucket = aws_s3_bucket.crc.id
  key    = var.lambda_file_name

  # Initialize with a provided code zipfile first
  # There is no need to concern about the code content, we just need a zip file
  source = "./${var.lambda_file_name}"

  # Then, ignore the upate from GitHub Actions
  lifecycle {
    ignore_changes = [ source, etag ]
  }
} 

# IAM Role that Lambda function uses
################################################################################

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
  name               = "${local.backend_name}-role"
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
          "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.backend_name}:*"
        ]
      }
    ]
  })
}

# IAM Role Policy for GitHub Actions to update the Lambda function
################################################################################

data "aws_iam_policy_document" "github_actions_lambda" {
    statement {
        effect = "Allow"

        actions = [
            "s3:PutObject",
            "s3:GetObject",
            "s3:ListBucket"
        ]

        resources = [
            "arn:aws:s3:::${var.lambda_s3_bucket_name}",
            "arn:aws:s3:::${var.lambda_s3_bucket_name}/*"
        ]
    }

    statement {
        effect = "Allow"

        actions = [
            "lambda:UpdateFunctionCode",
            "lambda:GetFunction"
        ]

        resources = [
            "arn:aws:lambda:${data.aws_region.current.region}.${data.aws_caller_identity.current.account_id}"
        ]
    }
}

resource "aws_iam_role_policy" "github_actions_lambda" {
  name = "GitHubActionsLambda"
  role = aws_iam_role.github_actions.name
  policy = data.aws_iam_policy_document.github_actions_lambda.json
}


################################################################################
# API Gateway
################################################################################

resource "aws_api_gateway_rest_api" "visitor_counter" {
  name = local.backend_name

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "visitor_counter" {
  rest_api_id = aws_api_gateway_rest_api.visitor_counter.id
  parent_id   = aws_api_gateway_rest_api.visitor_counter.root_resource_id
  path_part   = var.api_path
}

# POST Method
################################################################################

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


# OPTIONS Method (for CORS)
################################################################################

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
    "method.response.header.Access-Control-Allow-Origin"  = "'${var.full_domain_name}'"
  }
}

resource "aws_api_gateway_method_response" "visitor_counter_options" {
  rest_api_id = aws_api_gateway_rest_api.visitor_counter.id
  resource_id = aws_api_gateway_resource.visitor_counter.id
  http_method = aws_api_gateway_method.visitor_counter_options.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}


# Deployment and Stage
################################################################################

resource "aws_api_gateway_deployment" "visitor_counter" {
  rest_api_id = aws_api_gateway_rest_api.visitor_counter.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_rest_api.visitor_counter,
      aws_api_gateway_resource.visitor_counter,

      aws_api_gateway_method.visitor_counter_post,
      aws_api_gateway_integration.visitor_counter_post,
      
      aws_api_gateway_method.visitor_counter_options,
      aws_api_gateway_integration.visitor_counter_options,
      aws_api_gateway_integration_response.visitor_counter_options,
      aws_api_gateway_method_response.visitor_counter_options
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "visitor_counter" {
  rest_api_id   = aws_api_gateway_rest_api.visitor_counter.id
  deployment_id = aws_api_gateway_deployment.visitor_counter.id
  stage_name    = var.api_stage_name
}