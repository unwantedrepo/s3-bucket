############################
# Core
############################
variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket"
  validation {
    condition     = length(var.bucket_name) >= 3
    error_message = "bucket_name must be at least 3 characters long."
  }
}

variable "force_destroy" {
  type        = bool
  description = "Allow bucket deletion"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "s3 bucket tags"
  default     = {}
}

############################
# Versioning
############################
variable "versioning_status" {
  type        = string
  description = "Bucket versioning status"
  default     = "Enabled"
  validation {
    condition     = contains(["Enabled", "Suspended"], var.versioning_status)
    error_message = "versioning_status must be Enabled or Suspended."
  }
}

############################
# Ownership & ACL
############################
variable "object_ownership" {
  type        = string
  description = "S3 object ownership setting"
  default     = "BucketOwnerEnforced"

  validation {
    condition = contains(
      ["BucketOwnerEnforced", "BucketOwnerPreferred", "ObjectWriter"],
      var.object_ownership
    )
    error_message = "Invalid object ownership value."
  }
}

variable "bucket_acl" {
  type        = string
  description = "Bucket ACL (only when ownership is not enforced)"
  default     = "private"
  validation {
    condition     = !contains(["public-read", "public-read-write"], var.bucket_acl)
    error_message = "Public ACLs are not allowed. Use bucket policies."
  }
  validation {
    condition = !(
      var.object_ownership == "BucketOwnerEnforced" &&
      var.bucket_acl != "private"
    )
    error_message = "bucket_acl must not be set when object_ownership is BucketOwnerEnforced."
  }
}

############################
# Public Access Block
############################
variable "public_access_block" {
  description = "Public access block configuration"
  type = object({
    enabled                 = bool
    block_public_acls       = optional(bool, true)
    block_public_policy     = optional(bool, true)
    ignore_public_acls      = optional(bool, true)
    restrict_public_buckets = optional(bool, true)
  })
  default = {
    enabled = true
  }
}

############################
# Encryption
############################
variable "encryption" {
  description = "s3 bucket encryption configuration"
  type = object({
    enabled            = bool
    algorithm          = optional(string, "AES256")
    kms_key_id         = optional(string)
    bucket_key_enabled = optional(bool, true)
  })
  default = {
    enabled = true
  }
  validation {
    condition = !(
      var.encryption.algorithm == "AES256" &&
      try(var.encryption.kms_key_id, null) != null
    )
    error_message = "kms_key_id cannot be set when using AES256."
  }
  validation {
    condition = !(
      var.encryption.algorithm == "aws:kms" &&
      try(var.encryption.kms_key_id, null) == null
    )
    error_message = "kms_key_id must be provided when using aws:kms encryption."
  }
}

############################
# lifecycle_rules
############################
variable "lifecycle_rules" {
  description = "List of S3 lifecycle rules"
  type = list(object({
    id      = string
    enabled = bool
    filter = optional(object({
      prefix = optional(string)
      tags   = optional(map(string))
    }))
    transition = optional(list(object({
      days          = number
      storage_class = string
    })))
    expiration = optional(object({
      days                         = optional(number)
      expired_object_delete_marker = optional(bool)
    }))
    noncurrent_version_transition = optional(list(object({
      noncurrent_days = number
      storage_class   = string
    })))
    noncurrent_version_expiration = optional(object({
      noncurrent_days = number
    }))

    abort_incomplete_multipart_upload = optional(object({
      days_after_initiation = number
    }))
  }))
  default = []
  validation {
    condition = alltrue([
      for r in var.lifecycle_rules :
      (
        length(try(r.transition, [])) > 0 ||
        r.expiration != null ||
        r.noncurrent_version_expiration != null ||
        length(try(r.noncurrent_version_transition, [])) > 0 ||
        r.abort_incomplete_multipart_upload != null
      )
    ])
    error_message = "Each lifecycle rule must define at least one action."
  }
}
############################
# Static Website
############################
variable "enable_static_hosting" {
  type        = bool
  description = "Enable static website hosting"
  default     = false
  validation {
    condition = !(
      var.enable_static_hosting &&
      var.public_access_block.enabled &&
      (
        var.public_access_block.block_public_policy ||
        var.public_access_block.block_public_acls
      )
    )
    error_message = "Static hosting requires public access via bucket policy and ACLs."
  }
}

variable "website_index_document" {
  type        = string
  description = "Index document for S3 static website"
  default     = "index.html"
  validation {
    condition = !(
      var.enable_static_hosting && var.website_index_document == ""
    )
    error_message = "website_index_document cannot be empty when static hosting is enabled."
  }
}

variable "website_error_document" {
  type        = string
  description = "Error document for S3 static website"
  default     = "error.html"
  validation {
    condition = !(
      var.enable_static_hosting && var.website_error_document == ""
    )
    error_message = "website_error_document cannot be empty when static hosting is enabled."
  }
}

variable "upload_website_objects" {
  type        = bool
  description = "Whether to upload website files from html_folder_path"
  default     = true
}

variable "html_folder_path" {
  type        = string
  description = "Path to HTML files for upload (used only when upload_website_objects = true)"
  default     = null
  validation {
    condition = !(
      var.enable_static_hosting &&
      var.upload_website_objects &&
      var.html_folder_path == null
    )
    error_message = "html_folder_path must be set when upload_website_objects is true."
  }
}

############################
# Object Prefixes (Directories)
############################
variable "object_prefixes" {
  type        = list(string)
  description = "List of S3 prefixes (directories) to create"
  default     = []
}

############################
# Access Logging
############################
variable "access_logging" {
  description = "S3 access logging configuration"
  type = object({
    enabled       = bool
    target_bucket = string
    target_prefix = optional(string, "logs/")
  })
  default = {
    enabled       = false
    target_bucket = ""
  }
  validation {
    condition = !(
      var.access_logging.enabled &&
      (
        var.access_logging.target_bucket == "" ||
        var.access_logging.target_bucket == var.bucket_name
      )
    )
    error_message = "When access_logging is enabled, target_bucket must be set and must be different from the source bucket."
  }
}

############################
# Policy (External)
############################
variable "bucket_policy_json" {
  type        = string
  default     = null
  description = "Inline bucket policy JSON"

  validation {
    condition = (
      var.bucket_policy_json == null ||
      (
        var.bucket_policy_file == null &&
        length(var.bucket_policy_documents) == 0
      )
    )
    error_message = "Provide only one of bucket_policy_json, bucket_policy_file, or bucket_policy_documents."
  }
}

variable "bucket_policy_file" {
  type        = string
  description = "Path to bucket policy JSON file"
  default     = null
}

variable "bucket_policy_documents" {
  type        = list(string)
  description = "List of policy document JSON fragments"
  default     = []
  validation {
    condition = alltrue([
      for doc in var.bucket_policy_documents :
      can(jsondecode(doc))
    ])
    error_message = "All bucket_policy_documents must be valid JSON."
  }
}

############################
# Object Lock
############################
variable "object_lock" {
  description = "S3 Object Lock configuration"
  type = object({
    enabled         = bool
    mode            = optional(string, "GOVERNANCE")
    retention_days  = optional(number)
    retention_years = optional(number)
  })
  default = {
    enabled = false
  }
  validation {
    condition = !(
      var.object_lock.enabled &&
      var.versioning_status != "Enabled"
    )
    error_message = "Object Lock requires versioning_status = Enabled."
  }
  validation {
    condition = !(
      var.object_lock.enabled &&
      var.object_lock.retention_days == null &&
      var.object_lock.retention_years == null
    )
    error_message = "Object Lock requires either retention_days or retention_years."
  }
  validation {
    condition = !(
      var.versioning_status == "Suspended" &&
      var.object_lock.enabled
    )
    error_message = "Object Lock cannot be enabled when versioning is Suspended."
  }
}

############################
# Replication
############################
variable "replication" {
  description = "S3 replication configuration"
  type = object({
    enabled  = bool
    role_arn = string
    destination = object({
      bucket_arn    = string
      storage_class = optional(string, "STANDARD")
      kms_key_id    = optional(string)
      account_id    = optional(string)
    })
    prefix = optional(string)
  })
  default = {
    enabled  = false
    role_arn = ""
    destination = {
      bucket_arn = ""
    }
  }
  validation {
    condition = !(
      var.replication.enabled &&
      var.versioning_status != "Enabled"
    )
    error_message = "Replication requires versioning_status = Enabled."
  }
  validation {
    condition = !(
      var.replication.enabled &&
      var.replication.role_arn == ""
    )
    error_message = "replication.role_arn must be provided when replication is enabled."
  }
  validation {
    condition = !(
      var.replication.enabled &&
      var.replication.destination.bucket_arn == ""
    )
    error_message = "replication.destination.bucket_arn must be set when replication is enabled."
  }
}

############################
# Access Points
############################
variable "access_points" {
  description = "S3 access points configuration"
  type = map(object({
    vpc_id = optional(string)
    policy = optional(string)
  }))
  default = {}
}

############################
# Event Hooks
############################
variable "event_notifications" {
  description = "S3 event notifications"
  type = object({
    enabled = bool
    lambda = optional(list(object({
      function_arn  = string
      events        = list(string)
      filter_prefix = optional(string)
      filter_suffix = optional(string)
    })), [])
    sqs = optional(list(object({
      queue_arn     = string
      events        = list(string)
      filter_prefix = optional(string)
      filter_suffix = optional(string)
    })), [])
    sns = optional(list(object({
      topic_arn     = string
      events        = list(string)
      filter_prefix = optional(string)
      filter_suffix = optional(string)
    })), [])
  })
  default = {
    enabled = false
  }
}

############################
# CloudWatch Alarms
############################
variable "cloudwatch_alarms" {
  description = "CloudWatch alarm configuration"
  type = object({
    enabled = bool
    alarms = optional(map(object({
      metric_name         = string
      threshold           = number
      alarm_actions       = list(string)
      namespace           = optional(string, "AWS/S3")
      statistic           = optional(string, "Sum")
      period              = optional(number, 300)
      evaluation_periods  = optional(number, 1)
      comparison_operator = optional(string, "GreaterThanThreshold")
    })), {})
  })
  default = {
    enabled = false
  }
}

############################
# s3 transfer acceleration
############################
variable "transfer_acceleration" {
  type        = bool
  description = "Enable S3 Transfer Acceleration"
  default     = false
}
############################
# s3 inventory reports
############################
variable "inventory" {
  description = "S3 inventory configuration"
  type = object({
    enabled                = bool
    destination_bucket_arn = string
    frequency              = optional(string, "Daily")
    format                 = optional(string, "Parquet")
    prefix                 = optional(string)
  })
  default = {
    enabled                = false
    destination_bucket_arn = ""
  }
  validation {
    condition = !(
      var.inventory.enabled &&
      var.inventory.destination_bucket_arn == ""
    )
    error_message = "Inventory destination bucket ARN must be set when inventory is enabled."
  }
  validation {
    condition = (
      var.inventory.format == null ||
      contains(["CSV", "ORC", "Parquet"], var.inventory.format)
    )
    error_message = "Inventory format must be CSV, ORC, or Parquet."
  }
}
############################
# Intelligent Tiering
############################
variable "intelligent_tiering" {
  description = "Enable S3 Intelligent Tiering"
  type = object({
    enabled                   = bool
    archive_access_days       = optional(number)
    deep_archive_access_days  = optional(number)
  })
  default = {
    enabled = false
  }
  validation {
    condition = !(
      var.intelligent_tiering.enabled &&
      var.intelligent_tiering.archive_access_days == null &&
      var.intelligent_tiering.deep_archive_access_days == null
    )
    error_message = "At least one tiering days value must be set when intelligent tiering is enabled."
  }
}