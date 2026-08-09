output "bucket_name" {
  description = "Set as CMD_S3_BUCKET."
  value       = aws_s3_bucket.hedgedoc.id
}

output "bucket_region" {
  description = "Set as CMD_S3_REGION."
  value       = var.aws_region
}

output "iam_user_name" {
  description = "Generate an access key for this user (console or CLI), then set CMD_S3_ACCESS_KEY_ID / CMD_S3_SECRET_ACCESS_KEY."
  value       = aws_iam_user.hedgedoc.name
}

output "iam_user_arn" {
  value = aws_iam_user.hedgedoc.arn
}
