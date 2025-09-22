Here’s a clean Terraform module to create a KMS key with alias and policy support:

# modules/kms/variables.tf
variable "kms_key_name" {
  type        = string
  description = "Alias name for the KMS key (without 'alias/')."
}

variable "description" {
  type        = string
  description = "Description of the KMS key."
}

variable "deletion_window_in_days" {
  type        = number
  default     = 30
  description = "Waiting period for KMS key deletion (7–30 days)."
}

variable "enable_key_rotation" {
  type        = bool
  default     = true
  description = "Enable automatic key rotation."
}

variable "policy_json" {
  type        = string
  description = "Path to a JSON policy file for the KMS key."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to the KMS key."
}

# modules/kms/main.tf
resource "aws_kms_key" "this" {
  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = var.enable_key_rotation
  policy                  = file(var.policy_json)
  tags                    = var.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.kms_key_name}"
  target_key_id = aws_kms_key.this.key_id
}

# modules/kms/outputs.tf
output "kms_key_id" {
  value       = aws_kms_key.this.key_id
  description = "KMS key ID."
}

output "kms_key_arn" {
  value       = aws_kms_key.this.arn
  description = "KMS key ARN."
}

output "kms_alias" {
  value       = aws_kms_alias.this.name
  description = "KMS key alias."
}

Example usage in root
module "kms" {
  source = "./modules/kms"

  kms_key_name            = "s3-replication-key"
  description             = "KMS key for S3 replication"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy_json             = "policies/kms-policy.json"

  tags = {
    Environment = "dev"
    App         = "efm"
  }
}
