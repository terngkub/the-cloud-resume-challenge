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