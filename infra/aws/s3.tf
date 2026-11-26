# Production S3 vault bucket (separate from staging). The Cloud Functions use it through
# S3_BUCKET_PRODUCTION; staging keeps the existing bucket (S3_BUCKET_STAGING).
# Objects stay private: clients only get short-lived presigned URLs from the Functions.

resource "aws_s3_bucket" "vault_production" {
  bucket = var.s3_production_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "vault_production" {
  bucket = aws_s3_bucket.vault_production.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "vault_production" {
  bucket                  = aws_s3_bucket.vault_production.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vault_production" {
  bucket = aws_s3_bucket.vault_production.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "vault_production" {
  bucket = aws_s3_bucket.vault_production.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Old versions are kept 30 days (accidental overwrite/delete recovery), then removed.
# Account deletion removes every version of the user's objects immediately (delete_my_account.js).
resource "aws_s3_bucket_lifecycle_configuration" "vault_production" {
  bucket = aws_s3_bucket.vault_production.id
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
  depends_on = [aws_s3_bucket_versioning.vault_production]
}

# Presigned browser uploads/downloads (Flutter web). Mobile apps do not use CORS.
resource "aws_s3_bucket_cors_configuration" "vault_production" {
  bucket = aws_s3_bucket.vault_production.id
  cors_rule {
    allowed_methods = ["GET", "PUT", "HEAD"]
    allowed_origins = var.cors_allowed_origins
    allowed_headers = ["content-type", "content-md5", "x-amz-*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# Deny any request that is not HTTPS.
resource "aws_s3_bucket_policy" "vault_production_tls_only" {
  bucket = aws_s3_bucket.vault_production.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.vault_production.arn, "${aws_s3_bucket.vault_production.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.vault_production]
}

# ---- Access logs (separate bucket, private, 365 days) ----
resource "aws_s3_bucket" "vault_production_logs" {
  bucket = "${var.s3_production_bucket_name}-logs"
}

resource "aws_s3_bucket_ownership_controls" "vault_production_logs" {
  bucket = aws_s3_bucket.vault_production_logs.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "vault_production_logs" {
  bucket                  = aws_s3_bucket.vault_production_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "vault_production_logs" {
  bucket = aws_s3_bucket.vault_production_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "vault_production_logs" {
  bucket = aws_s3_bucket.vault_production_logs.id
  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = 365
    }
  }
}

data "aws_caller_identity" "current" {}

# Only the S3 logging service, for this bucket's logs, in this account, may write logs.
resource "aws_s3_bucket_policy" "vault_production_logs" {
  bucket = aws_s3_bucket.vault_production_logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "S3ServerAccessLogsPolicy"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.vault_production_logs.arn}/access/*"
        Condition = {
          ArnLike      = { "aws:SourceArn" = aws_s3_bucket.vault_production.arn }
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.vault_production_logs.arn, "${aws_s3_bucket.vault_production_logs.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.vault_production_logs]
}

resource "aws_s3_bucket_logging" "vault_production" {
  bucket        = aws_s3_bucket.vault_production.id
  target_bucket = aws_s3_bucket.vault_production_logs.id
  target_prefix = "access/"
}

# ---- Least-privilege IAM per environment for the Cloud Functions ----
# Exactly the S3 calls the Functions make (s3_storage.js, delete_my_account.js): presigned
# PUT/GET, HEAD, single and batch deletes, version listing + version delete (account deletion),
# HeadBucket (ListBucket). Nothing else, one bucket each.
locals {
  vault_policy_statements = {
    production = var.s3_production_bucket_name
    staging    = var.s3_staging_bucket_name
  }
}

resource "aws_iam_policy" "functions_s3_vault" {
  for_each    = local.vault_policy_statements
  name        = "${var.project_name}-functions-s3-${each.key}"
  description = "Cloud Functions access to the ${each.key} S3 vault bucket only"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "BucketLevel"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:ListBucketVersions"]
        Resource = "arn:aws:s3:::${each.value}"
      },
      {
        Sid    = "ObjectLevel"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion",
        ]
        Resource = "arn:aws:s3:::${each.value}/*"
      },
    ]
  })
}

# Dedicated IAM user for the production Functions. Its access key is created by hand in the
# console (never in Terraform, so it is not stored in Terraform state) and goes straight into
# Firebase Secret Manager (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY).
resource "aws_iam_user" "functions_s3_production" {
  name = "${var.project_name}-functions-s3-production"
}

resource "aws_iam_user_policy_attachment" "functions_s3_production" {
  user       = aws_iam_user.functions_s3_production.name
  policy_arn = aws_iam_policy.functions_s3_vault["production"].arn
}

# The production Functions keep the five demo accounts' files in the STAGING bucket under
# demo/ (s3_bucket.js resolveS3BucketForUid). Allow exactly that prefix, nothing else there.
resource "aws_iam_policy" "functions_s3_demo_prefix" {
  name        = "${var.project_name}-functions-s3-demo-prefix"
  description = "Production Functions: demo/ prefix of the staging bucket only (demo accounts)"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListDemoPrefix"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:ListBucketVersions"]
        Resource = "arn:aws:s3:::${var.s3_staging_bucket_name}"
        Condition = {
          StringLike = { "s3:prefix" = ["demo/", "demo/*"] }
        }
      },
      {
        Sid      = "DemoObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:DeleteObjectVersion"]
        Resource = "arn:aws:s3:::${var.s3_staging_bucket_name}/demo/*"
      },
    ]
  })
}

resource "aws_iam_user_policy_attachment" "functions_s3_production_demo_prefix" {
  user       = aws_iam_user.functions_s3_production.name
  policy_arn = aws_iam_policy.functions_s3_demo_prefix.arn
}
