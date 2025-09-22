Thought for 18s

User wants a Terraform module that uses a JSON template for policy, where variables like account number and role name(s) are provided. The module should read the policy via templatefile with a variables map, allowing flexibility for both single roles and lists. I'll keep it concise, avoid defaults, and provide variables with clear descriptions.

I need to implement the policy template and variables map. I'll create a policy_template_path and a vars map for things like account_id and role_name. The template would include placeholders that

Done
# modules/kms/variables.tf
variable "kms_key_name" {
  type        = string
  description = "Alias (without 'alias/')."
}

variable "description" {
  type        = string
  description = "KMS key description."
}

variable "policy_template" {
  type        = string
  description = "Path to policy template file (e.g., policies/kms-policy.json.tpl)."
}

variable "policy_vars" {
  type        = map(string)
  description = "Vars for templatefile(), e.g. { account_id = \"123...\", role_arns_json = jsonencode([\"arn:...:role/x\"]) }"
}

variable "deletion_window_in_days" {
  type        = number
  description = "7–30."
}

variable "enable_key_rotation" {
  type        = bool
  description = "true/false."
}

variable "tags" {
  type        = map(string)
  description = "Tags."
}

# modules/kms/main.tf
resource "aws_kms_key" "this" {
  description             = var.description
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = var.enable_key_rotation
  policy                  = templatefile(var.policy_template, var.policy_vars)
  tags                    = var.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.kms_key_name}"
  target_key_id = aws_kms_key.this.key_id
}

# modules/kms/outputs.tf
output "kms_key_id"  { value = aws_kms_key.this.key_id }
output "kms_key_arn" { value = aws_kms_key.this.arn }
output "kms_alias"   { value = aws_kms_alias.this.name }

Example call (you provide the JSON template + vars)
module "kms" {
  source                  = "./modules/kms"
  kms_key_name            = "s3-repl-key"
  description             = "KMS for S3 replication"
  policy_template         = "policies/kms-policy.json.tpl"

  # You control account number and roles here
  policy_vars = {
    account_id      = var.account_id
    role_arns_json  = jsonencode([
      "arn:aws-us-gov:iam::${var.account_id}:role/s3-replication-role",
      "arn:aws-us-gov:iam::${var.account_id}:role/backup-role"
    ])
  }

  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = var.tags
}

Minimal template example you can edit (policies/kms-policy.json.tpl)
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RootFullAccess",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws-us-gov:iam::${account_id}:root" },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "RolesUseKey",
      "Effect": "Allow",
      "Principal": { "AWS": ${role_arns_json} },
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey"
      ],
      "Resource": "*"
    }
  ]
}


Use ${account_id} or any other placeholders you want; pass them via policy_vars. For multiple roles, pass role_arns_json = jsonencode([...]).

ChatGPT can make mistakes. Check important info.
