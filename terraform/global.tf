################################################################################
# CloudFront
################################################################################

# Certificate
################################################################################

data "aws_acm_certificate" "resume_website" {
  provider = aws.us-east-1
  domain   = var.root_domain_name
}

# Policies
################################################################################

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# Origin Information
################################################################################

resource "aws_cloudfront_origin_access_control" "resume_website" {
  name                              = var.full_domain_name
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

locals {
  api_gateway_origin_id = replace(aws_api_gateway_stage.visitor_counter.invoke_url, "/^https?://([^/]*).*/", "$1")
}

# Distribution
################################################################################

resource "aws_cloudfront_distribution" "resume_website" {
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  default_root_object = var.website_index_file
  aliases             = [var.full_domain_name]

  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn            = data.aws_acm_certificate.resume_website.arn
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  tags = {
    "Name" = var.full_domain_name
  }
  tags_all = {
    "Name" = var.full_domain_name
  }

  # S3
  ################################################################################

  origin {
    domain_name              = aws_s3_bucket.resume_website.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.resume_website.id
    origin_id                = var.full_domain_name
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = var.full_domain_name
    viewer_protocol_policy = "allow-all"
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true
  }

  # API Gateway
  ################################################################################

  origin {
    domain_name = local.api_gateway_origin_id
    origin_id = local.api_gateway_origin_id
    
    custom_origin_config {
      http_port = 80
      https_port = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols = ["TLSv1.2"]
    }
  }

  ordered_cache_behavior {
    path_pattern = "/${aws_api_gateway_stage.visitor_counter.stage_name}/*"
    target_origin_id = local.api_gateway_origin_id
    compress = true
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cache_policy_id = data.aws_cloudfront_cache_policy.caching_disabled.id
    cached_methods = ["GET", "HEAD"]
  }
}


################################################################################
# GitHub Actions IAM Role
################################################################################

data "aws_iam_policy_document" "github_actions_assume" {
    statement {
        effect = "Allow"

        principals {
          type = "Federated"
          identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
        }

        actions = ["sts:AssumeRoleWithWebIdentity"]

        condition {
            test = "StringEquals"
            variable = "token.actions.githubusercontent.com:aud"
            values = ["sts.amazonaws.com"]
        }
        condition {
            test = "StringLike"
            variable = "token.actions.githubusercontent.com:sub"
            values = ["repo:terngkub/the-cloud-resume-challenge:*"]
        }
    }
}

resource "aws_iam_role" "github_actions" {
    name = "crc-github-actions-role"
    assume_role_policy = data.aws_iam_policy_document.github_actions_assume.json
}

resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
