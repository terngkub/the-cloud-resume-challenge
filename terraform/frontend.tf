################################################################################
# Website
################################################################################

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

data "aws_iam_policy_document" "resume_website" {
    statement {
        effect = "Allow"

        principals {
          type        = "Service"
          identifiers = ["cloudfront.amazonaws.com"]
        }

        actions = [
            "s3:GetObject",
        ]

        resources = ["${aws_s3_bucket.resume_website.arn}/*"]

        condition {
          test     = "StringEquals"
          variable = "AWS:SourceArn"
          values   = [aws_cloudfront_distribution.resume_website.arn]
        }
    }
}

resource "aws_s3_bucket_policy" "resume_website" {
  bucket = aws_s3_bucket.resume_website.id
  policy = data.aws_iam_policy_document.resume_website.json
}

# IAM Role Policy for GitHub Actions to sync the S3
################################################################################

data "aws_iam_policy_document" "github_actions_website" {
    statement {
        effect = "Allow"

        actions = [
            "s3:PutObject",
            "s3:GetObject",
            "s3:ListBucket",
            "s3:DeleteObject"
        ]

        resources = [
            "arn:aws:s3:::${var.full_domain_name}",
            "arn:aws:s3:::${var.full_domain_name}/*"
        ]
    }
}

resource "aws_iam_role_policy" "github_actions_website" {
  name = "GitHubActionsWebsite"
  role = aws_iam_role.github_actions.name
  policy = data.aws_iam_policy_document.github_actions_website.json
}