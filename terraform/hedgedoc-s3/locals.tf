locals {
  common_tags = {
    project     = var.project
    environment = var.environment
    owner       = var.owner
    ManagedBy   = "terraform"
  }

  name_prefix = coalesce(var.name_prefix, var.project)
  base_name   = "${local.name_prefix}-${var.service_name}"

  bucket_name   = coalesce(var.bucket_name, "${local.base_name}-uploads")
  iam_user_name = coalesce(var.iam_user_name, "${local.base_name}-s3")
}
