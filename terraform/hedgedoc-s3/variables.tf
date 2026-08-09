variable "aws_region" {
  description = "AWS region for the bucket. Must match CMD_S3_REGION in HedgeDoc."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Common prefix for resource names across services. Defaults to project."
  type        = string
  default     = null
}

variable "service_name" {
  description = "Service this stack belongs to; combined with name_prefix for resource names."
  type        = string
  default     = "hedgedoc"
}

variable "bucket_name" {
  description = "Override the derived bucket name. Must be globally unique if set."
  type        = string
  default     = null
}

variable "iam_user_name" {
  description = "Override the derived IAM user name."
  type        = string
  default     = null
}

variable "upload_prefix" {
  description = "Key prefix objects are stored under. Match CMD_S3_FOLDER."
  type        = string
  default     = "uploads"
}

variable "project" {
  type    = string
  default = "homelab-s2n"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "owner" {
  type    = string
  default = "donkeysharp"
}
