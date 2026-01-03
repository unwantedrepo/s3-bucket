locals {
  bucket_name = var.bucket_name
  html_files = (
    var.enable_static_hosting && var.html_folder_path != null
    ? fileset(var.html_folder_path, "*.html")
    : []
  )
  resolved_bucket_policy = (
    var.bucket_policy_json != null ? var.bucket_policy_json :
    var.bucket_policy_file != null ? file(var.bucket_policy_file) :
    length(var.bucket_policy_documents) > 0 ? jsonencode({
      Version = "2012-10-17"
      Statement = flatten([
        for doc in var.bucket_policy_documents :
        jsondecode(doc).Statement
      ])
    }) :
    null
  )
}

locals {
  intelligent_tiering_rules = [
    for tier in [
      var.intelligent_tiering.archive_access_days != null ? {
        access_tier = "ARCHIVE_ACCESS"
        days        = var.intelligent_tiering.archive_access_days
      } : null,

      var.intelligent_tiering.deep_archive_access_days != null ? {
        access_tier = "DEEP_ARCHIVE_ACCESS"
        days        = var.intelligent_tiering.deep_archive_access_days
      } : null
    ] : tier if tier != null
  ]
}
############################
# S3 Bucket
############################
resource "aws_s3_bucket" "this" {
  bucket              = local.bucket_name
  force_destroy       = var.force_destroy
  object_lock_enabled = var.object_lock.enabled
  tags = var.tags
}

############################
# Versioning
############################
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_status
  }
}

############################
# Ownership Controls
############################
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = var.object_ownership
  }
}

############################
# ACL (only if allowed)
############################
resource "aws_s3_bucket_acl" "this" {
  count      = var.object_ownership == "BucketOwnerEnforced" ? 0 : 1
  bucket     = aws_s3_bucket.this.id
  acl        = var.bucket_acl
  depends_on = [aws_s3_bucket_ownership_controls.this]
}

############################
# Public Access Block
############################
resource "aws_s3_bucket_public_access_block" "this" {
  count  = var.public_access_block.enabled ? 1 : 0
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.public_access_block.block_public_acls
  block_public_policy     = var.public_access_block.block_public_policy
  ignore_public_acls      = var.public_access_block.ignore_public_acls
  restrict_public_buckets = var.public_access_block.restrict_public_buckets
}

############################
# Encryption
############################
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  count  = var.encryption.enabled ? 1 : 0
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.encryption.kms_key_id != null ? "aws:kms" : var.encryption.algorithm
      kms_master_key_id = var.encryption.kms_key_id
    }
    bucket_key_enabled = var.encryption.bucket_key_enabled
  }
}

############################
# Lifecycle Configuration
############################
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = length(var.lifecycle_rules) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      dynamic "filter" {
        for_each = rule.value.filter != null ? [rule.value.filter] : []
        content {
          dynamic "and" {
            for_each = (
              try(filter.value.prefix, null) != null ||
              try(filter.value.tags, null) != null
            ) ? [1] : []
            content {
              prefix = try(filter.value.prefix, null)
              tags   = try(filter.value.tags, null)
            }
          }
        }
      }

      dynamic "transition" {
        for_each = rule.value.transition != null ? rule.value.transition : []
        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }

      dynamic "expiration" {
        for_each = rule.value.expiration != null ? [rule.value.expiration] : []
        content {
          days                         = try(expiration.value.days, null)
          expired_object_delete_marker = try(expiration.value.expired_object_delete_marker, null)
        }
      }

      dynamic "noncurrent_version_transition" {
        for_each = (
          rule.value.noncurrent_version_transition != null
          ? rule.value.noncurrent_version_transition
          : []
        )
        content {
          noncurrent_days = noncurrent_version_transition.value.noncurrent_days
          storage_class   = noncurrent_version_transition.value.storage_class
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration != null ? [rule.value.noncurrent_version_expiration] : []
        content {
          noncurrent_days = noncurrent_version_expiration.value.noncurrent_days
        }
      }

      dynamic "abort_incomplete_multipart_upload" {
        for_each = rule.value.abort_incomplete_multipart_upload != null ? [rule.value.abort_incomplete_multipart_upload] : []
        content {
          days_after_initiation = abort_incomplete_multipart_upload.value.days_after_initiation
        }
      }
    }
  }
}

###############################
# # Intelligent Tiering
###############################
resource "aws_s3_bucket_intelligent_tiering_configuration" "this" {
  count  = (
    var.intelligent_tiering.enabled &&
    length(local.intelligent_tiering_rules) > 0
  ) ? 1 : 0

  bucket = aws_s3_bucket.this.id
  name   = "default-tiering"
  status = "Enabled"

  dynamic "tiering" {
    for_each = local.intelligent_tiering_rules
    content {
      access_tier = tiering.value.access_tier
      days        = tiering.value.days
    }
  }
}

############################
# Prefix / Directory Creation
############################
resource "aws_s3_object" "prefixes" {
  for_each = (
    var.object_lock.enabled
    ? toset([])
    : toset(var.object_prefixes)
  )

  bucket  = aws_s3_bucket.this.id
  key     = "${trim(each.value, "/")}/"
  content = ""
}

############################
# Static Website Hosting
############################
resource "aws_s3_bucket_website_configuration" "this" {
  count  = var.enable_static_hosting ? 1 : 0
  bucket = aws_s3_bucket.this.id

  index_document {
    suffix = var.website_index_document
  }

  error_document {
    key = var.website_error_document
  }
}

############################
# Optional HTML Upload
############################
resource "aws_s3_object" "html" {
  for_each = (
    var.enable_static_hosting && var.upload_website_objects
    ? { for f in local.html_files : f => f }
    : {}
  )
  bucket       = aws_s3_bucket.this.id
  key          = each.key
  source       = "${var.html_folder_path}/${each.value}"
  content_type = lookup(
    {
      html = "text/html"
      css  = "text/css"
      js   = "application/javascript"
    },
    split(".", each.key)[length(split(".", each.key)) - 1], "binary/octet-stream"
  )
}

############################
# Access Logging
############################
resource "aws_s3_bucket_logging" "this" {
  count  = var.access_logging.enabled ? 1 : 0
  bucket = aws_s3_bucket.this.id

  target_bucket = var.access_logging.target_bucket
  target_prefix = var.access_logging.target_prefix
}

############################
# Bucket Policy (External)
############################
resource "aws_s3_bucket_policy" "this" {
  count  = local.resolved_bucket_policy != null ? 1 : 0
  bucket = aws_s3_bucket.this.id
  policy = local.resolved_bucket_policy

  depends_on = [aws_s3_bucket_public_access_block.this]
}

############################
# Object Lock Configuration
############################
resource "aws_s3_bucket_object_lock_configuration" "this" {
  count  = var.object_lock.enabled ? 1 : 0
  bucket = aws_s3_bucket.this.id
  depends_on = [
    aws_s3_bucket.this,
    aws_s3_bucket_versioning.this
  ]
  rule {
    default_retention {
      mode  = var.object_lock.mode
      days  = var.object_lock.retention_days
      years = var.object_lock.retention_years
    }
  }
}

############################
# Replication
############################
resource "aws_s3_bucket_replication_configuration" "this" {
  count      = var.replication.enabled ? 1 : 0
  bucket     = aws_s3_bucket.this.id
  role       = var.replication.role_arn
  depends_on = [aws_s3_bucket_versioning.this]
  rule {
    id     = "replication"
    status = "Enabled"
    filter {
      prefix = try(var.replication.prefix, "")
    }

    destination {
      bucket        = var.replication.destination.bucket_arn
      storage_class = var.replication.destination.storage_class
      account       = try(var.replication.destination.account_id, null)

      dynamic "encryption_configuration" {
        for_each = try(var.replication.destination.kms_key_id, null) != null ? [1] : []
        content {
          replica_kms_key_id = var.replication.destination.kms_key_id
        }
      }
    }
  }
}

############################
# Access Points
############################
resource "aws_s3_access_point" "this" {
  for_each = var.access_points

  name   = each.key
  bucket = aws_s3_bucket.this.id

  dynamic "vpc_configuration" {
    for_each = each.value.vpc_id != null ? [1] : []
    content {
      vpc_id = each.value.vpc_id
    }
  }

  policy = each.value.policy
}

############################
# Event Notifications
############################
resource "aws_s3_bucket_notification" "this" {
  count      = var.event_notifications.enabled ? 1 : 0
  bucket     = aws_s3_bucket.this.id
  depends_on = [aws_s3_bucket.this]
  dynamic "lambda_function" {
    for_each = var.event_notifications.lambda
    content {
      lambda_function_arn = lambda_function.value.function_arn
      events              = lambda_function.value.events
      filter_prefix       = try(lambda_function.value.filter_prefix, null)
      filter_suffix       = try(lambda_function.value.filter_suffix, null)
    }
  }

  dynamic "queue" {
    for_each = var.event_notifications.sqs
    content {
      queue_arn     = queue.value.queue_arn
      events        = queue.value.events
      filter_prefix = try(queue.value.filter_prefix, null)
      filter_suffix = try(queue.value.filter_suffix, null)
    }
  }

  dynamic "topic" {
    for_each = var.event_notifications.sns
    content {
      topic_arn     = topic.value.topic_arn
      events        = topic.value.events
      filter_prefix = try(topic.value.filter_prefix, null)
      filter_suffix = try(topic.value.filter_suffix, null)
    }
  }
}

############################
# CloudWatch Alarms
############################
resource "aws_cloudwatch_metric_alarm" "s3" {
  for_each = var.cloudwatch_alarms.enabled ? var.cloudwatch_alarms.alarms : {}

  alarm_name          = "${aws_s3_bucket.this.bucket}-${each.key}"
  metric_name         = each.value.metric_name
  namespace           = each.value.namespace
  statistic           = each.value.statistic
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison_operator
  alarm_actions       = each.value.alarm_actions

  dimensions = {
    BucketName  = aws_s3_bucket.this.bucket
    StorageType = "AllStorageTypes"
  }
}

###############################
# s3 transfer accelerate config
###############################
resource "aws_s3_bucket_accelerate_configuration" "this" {
  count  = var.transfer_acceleration ? 1 : 0
  bucket = aws_s3_bucket.this.id
  status = "Enabled"
}

###############################
# # Inventory reports config
###############################
resource "aws_s3_bucket_inventory" "this" {
  count  = var.inventory.enabled ? 1 : 0
  bucket = aws_s3_bucket.this.id
  name   = "inventory"
  included_object_versions = "All"
  schedule {
    frequency = var.inventory.frequency
  }
  destination {
    bucket {
      bucket_arn = var.inventory.destination_bucket_arn
      format     = var.inventory.format
      prefix     = var.inventory.prefix
    }
  }
}
