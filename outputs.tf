output "bucket_name" {
  value = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}

output "bucket_id" {
  value = aws_s3_bucket.this.id
}

output "bucket_regional_domain_name" {
  value = aws_s3_bucket.this.bucket_regional_domain_name
}

output "replication_destination_bucket_arn" {
  description = "Replication destination bucket ARN (if enabled)"
  value       = var.replication.enabled ? var.replication.destination.bucket_arn : null
}

output "website_endpoint" {
  description = "S3 static website endpoint (if enabled)"
  value = (
    var.enable_static_hosting
    ? aws_s3_bucket_website_configuration.this[0].website_endpoint
    : null
  )
}