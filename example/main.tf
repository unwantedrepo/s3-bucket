provider "aws" {
  region     = "eu-west-1"
}
data "aws_caller_identity" "current" {}
module "s3_bucket" {
  source            = "../../"
  bucket_name       = "${var.app_name}-${var.environment}-s3"
  versioning_status = "Enabled"
  # Encryption
  encryption = {
    enabled = true
    #kms_key_id = "kms-key-id" # Optional KMS Key ID for SSE-KMS
  }
  # Object prefixes (directories)
  object_prefixes = [
    "incoming/",
    "processed/",
    "archive/",
    "tmp"
  ]

  object_lock = {
    enabled        = true
    mode           = "COMPLIANCE"
    retention_days = 365
  }
  # Access logging
  access_logging = {
    enabled       = true
    target_bucket = "logging-sfd"
    target_prefix = "s3-access/"
  }
  access_points = {
    app = {
      vpc_id = "vpc-0bb6ebf8c0d0d4616"
      #policy = data.aws_iam_policy_document.ap_app.json
      policy = file("${path.module}/policies/ap-app.json")
    }
  }
  # Lifecycle Rules
  lifecycle_rules = [
    # Rule 1: Logs lifecycle (prefix based)
    {
      id      = "logs-lifecycle"
      enabled = true
      filter  = { prefix = "logs/" }
      transition = [
        { days = 30, storage_class = "STANDARD_IA" },
        { days = 60, storage_class = "INTELLIGENT_TIERING" },
        { days = 180, storage_class = "GLACIER" },
        { days = 365, storage_class = "DEEP_ARCHIVE" }
      ]
      expiration = {
        days = 365
      }
    },
    # Rule 2: Application data (tag based)
    {
      id      = "app-data"
      enabled = true
      filter = {
        tags = { data_type = "app", owner = "backend" }
      }
      transition = [
        { days = 30, storage_class = "STANDARD_IA" },
        { days = 60, storage_class = "INTELLIGENT_TIERING" },
        { days = 180, storage_class = "GLACIER" },
        { days = 365, storage_class = "DEEP_ARCHIVE" }
      ]
      noncurrent_version_transition = [
        { noncurrent_days = 30, storage_class = "STANDARD_IA" },
        { noncurrent_days = 90, storage_class = "GLACIER" },
        { noncurrent_days = 180, storage_class = "DEEP_ARCHIVE" }
      ]
      noncurrent_version_expiration = {
        noncurrent_days = 365
      }
    },
    # Rule 3: Temporary files (fast expiry)
    {
      id         = "tmp-files"
      enabled    = true
      filter     = { prefix = "tmp/" }
      expiration = { days = 7 }
    },
    # Rule 4: abort multipart uploads
    {
      id      = "abort-multipart-uploads"
      enabled = true
      abort_incomplete_multipart_upload = {
        days_after_initiation = 7
      }
    },
  ]
  # Intelligent Tiering
  intelligent_tiering = {
    enabled                  = true
    archive_access_days      = 90
    deep_archive_access_days = 180
  }
  # Tags
  tags = var.tags
}
