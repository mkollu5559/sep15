# modules/sns_topic/main.tf
resource "aws_sns_topic" "this" {
  name            = var.topic_name
  kms_master_key_id = var.kms_key_id
  tags            = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.subscriber_emails)
  topic_arn = aws_sns_topic.this.arn
  protocol  = "email"
  endpoint  = each.value
}
hcl
Copy code
# modules/sns_topic/variables.tf
variable "topic_name" {
  description = "SNS topic name"
  type        = string
}

variable "kms_key_id" {
  description = "KMS key ID/ARN for server-side encryption (optional)"
  type        = string
  default     = null
}

variable "subscriber_emails" {
  description = "List of email addresses to subscribe"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to the SNS topic"
  type        = map(string)
  default     = {}
}
hcl
Copy code
# modules/sns_topic/outputs.tf
output "topic_arn" {
  value = aws_sns_topic.this.arn
}

output "subscription_arns" {
  value = [for s in aws_sns_topic_subscription.email : s.arn]
}
hcl
Copy code
# calling module
module "efm_team_notifications" {
  source            = "./modules/sns_topic"
  topic_name        = "EFM_Team_Notification_All_Lambda_Functions"
  kms_key_id        = var.kms_key_id
  subscriber_emails = [
  ]
  tags = var.tags_west
}



