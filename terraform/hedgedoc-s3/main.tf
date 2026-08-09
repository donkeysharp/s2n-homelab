resource "aws_s3_bucket" "hedgedoc" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_ownership_controls" "hedgedoc" {
  bucket = aws_s3_bucket.hedgedoc.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Personally I hate having s3 buckets, but unfortunately
# hedgedoc only accepts this, as imgur access for client 
# applications does not exists anymore :(
resource "aws_s3_bucket_public_access_block" "hedgedoc" {
  bucket = aws_s3_bucket.hedgedoc.id

  block_public_acls       = false
  ignore_public_acls      = false
  block_public_policy     = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      aws_s3_bucket.hedgedoc.arn,
      "${aws_s3_bucket.hedgedoc.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "hedgedoc" {
  bucket = aws_s3_bucket.hedgedoc.id
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.hedgedoc]
}

resource "aws_iam_user" "hedgedoc" {
  name = local.iam_user_name
}

data "aws_iam_policy_document" "hedgedoc_uploads" {
  statement {
    sid    = "HedgeDocUploads"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:GetObject",
      "s3:DeleteObject",
    ]

    resources = ["${aws_s3_bucket.hedgedoc.arn}/${var.upload_prefix}/*"]
  }
}

resource "aws_iam_user_policy" "hedgedoc_uploads" {
  name   = "${local.base_name}-s3-uploads"
  user   = aws_iam_user.hedgedoc.name
  policy = data.aws_iam_policy_document.hedgedoc_uploads.json
}
