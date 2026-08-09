terraform {
  # Partial backend config: bucket comes from an unversioned file at init time.
  #   terraform init -backend-config=backend.hcl
  backend "s3" {
    key     = "hedgedoc-s3/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
