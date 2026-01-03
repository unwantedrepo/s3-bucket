
# Terraform Module: AWS S3 Bucket

## Overview

This module provisions an **enterprise-ready AWS S3 bucket** with security, compliance, and extensibility as first-class concerns.

It is designed for **platform teams** and **application teams** alike, enabling:
- Secure defaults
- Optional advanced features (replication, object lock, access points, events, monitoring)
- Environment-specific policy control
- Clean separation of responsibilities

This module **does NOT manage Terraform state buckets** and **does NOT enforce lifecycle meta-arguments**, keeping it reusable and safe.

---

## Features & Capabilities

### Core Bucket
- Versioning
- Ownership controls
- Public access block
- Server-side encryption (SSE-S3 / SSE-KMS)
- Tags

### Lifecycle Management
- Intelligent-Tiering
- IA / Glacier transitions
- Non-current version expiry

### Security & Compliance
- Object Lock (Governance / Compliance)
- Externalized bucket policies
- Access logging
- Public access controls

### Access & Integration
- Static website hosting
- Object prefix (directory) creation
- HTML upload
- Access Points (VPC / policy-based)

### Automation & Observability
- Event notifications (Lambda / SQS / SNS)
- CloudWatch alarms
- Cross-region replication

---

## Module Usage

See the [examples/](./examples) directory for feature-specific usage:

- [Basic bucket](./examples/basic)
- [Encrypted bucket (KMS)](./examples/encrypted)
- [Static website hosting](./examples/website)
- Replication
- Object Lock
- Access Points
- Event Notifications
- CloudWatch Monitoring

### Basic Bucket

```hcl
module "s3_basic" {
  source      = "./modules/s3"
  bucket_name = "my-app-bucket"
}
```

---

### Encrypted Bucket with KMS

```hcl
module "s3_secure" {
  source      = "./modules/s3"
  bucket_name = "secure-bucket"

  encryption = {
    enabled    = true
    kms_key_id = aws_kms_key.s3.arn
  }
}
```

---

### Bucket with Lifecycle Rules

```hcl
module "s3_lifecycle" {
  source      = "./modules/s3"
  bucket_name = "archive-bucket"

  lifecycle_rules = {
    enabled              = true
    archive_ia_days      = 90
    archive_glacier_days = 180
  }
}
```

---

### Static Website Hosting

```hcl
module "s3_website" {
  source      = "./modules/s3"
  bucket_name = "my-static-site"

  enable_static_hosting = true
  html_folder_path     = "./site"

  public_access_block = {
    enabled             = true
    block_public_policy = false
  }
}
```

---

### Bucket Policy (Inline JSON)

```hcl
module "s3_policy" {
  source      = "./modules/s3"
  bucket_name = "policy-bucket"

  bucket_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "arn:aws:s3:::policy-bucket/*"
    }]
  })
}
```

---

### Policy from File

```hcl
module "s3_policy_file" {
  source      = "./modules/s3"
  bucket_name = "file-policy-bucket"

  bucket_policy_file = "${path.module}/policy.json"
}
```

---

### Object Lock (Compliance)

```hcl
module "s3_object_lock" {
  source      = "./modules/s3"
  bucket_name = "locked-bucket"

  versioning_status = "Enabled"

  object_lock = {
    enabled        = true
    mode           = "COMPLIANCE"
    retention_days = 365
  }
}
```

---

### Replication

```hcl
module "s3_replication" {
  source      = "./modules/s3"
  bucket_name = "primary-bucket"

  replication = {
    enabled   = true
    role_arn = aws_iam_role.replication.arn
    destination = {
      bucket_arn = "arn:aws:s3:::dr-bucket"
    }
  }
}
```

---

### Access Logging

```hcl
module "s3_logging" {
  source      = "./modules/s3"
  bucket_name = "source-bucket"

  access_logging = {
    enabled       = true
    target_bucket = "log-bucket"
  }
}
```

> Ensure the target bucket allows `s3:PutObject` from `logging.s3.amazonaws.com`.

---

### Access Points

```hcl
module "s3_access_points" {
  source      = "./modules/s3"
  bucket_name = "ap-bucket"

  access_points = {
    app = {
      vpc_id = "vpc-123456"
    }
  }
}
```

---

### Event Notifications

```hcl
module "s3_events" {
  source      = "./modules/s3"
  bucket_name = "event-bucket"

  event_notifications = {
    enabled = true
    lambda = [
      {
        function_arn = aws_lambda_function.handler.arn
        events        = ["s3:ObjectCreated:*"]
      }
    ]
  }
}
```

---

### CloudWatch Alarms

```hcl
module "s3_monitoring" {
  source      = "./modules/s3"
  bucket_name = "monitored-bucket"

  cloudwatch_alarms = {
    enabled = true
    alarms = {
      size_alarm = {
        metric_name   = "BucketSizeBytes"
        threshold     = 1000000000
        alarm_actions = [aws_sns_topic.alerts.arn]
      }
    }
  }
}
```

---

## Outputs

- `bucket_name`
- `bucket_arn`
- `bucket_domain_name`
- `bucket_regional_domain_name`
- `replication_destination_bucket_arn`
- `website_endpoint`
- `access_points`

---

## Best Practices

- Enforce `prevent_destroy` at **root module / environment layer**
- Manage bucket policies externally per environment
- Use Object Lock only with versioning enabled
- Use separate buckets for access logs
- Apply CloudFront in front of public websites

---

## Terraform Compatibility

- Terraform >= 1.10
- AWS Provider >= 5.30

---

## Ownership
IMS Tooling Team
