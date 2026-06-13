locals {
  name_prefix = "${var.project}-${random_string.suffix.result}"

  default_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  web = {
    container_image    = "ghcr.io/platformfuzz/bedrock-image-analyzer:latest"
    container_port     = 8000
    health_check_path  = "/health"
    bedrock_model_id   = "au.anthropic.claude-sonnet-4-6"
    bedrock_max_tokens = 1024
  }

  # Strip geo/global prefix for foundation-model ARNs (e.g. au.anthropic.claude-sonnet-4-6 → anthropic.claude-sonnet-4-6).
  bedrock_model_base = replace(local.web.bedrock_model_id, "/^(global|us|eu|au|apac|jp)\\./", "")

  bedrock_is_inference_profile = can(regex("^(global|us|eu|au|apac|jp)\\.", local.web.bedrock_model_id))

  bedrock_inference_profile_arn = "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/${local.web.bedrock_model_id}"

  bedrock_foundation_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/${local.bedrock_is_inference_profile ? local.bedrock_model_base : local.web.bedrock_model_id}"

  # AU profiles route to Sydney and Melbourne foundation models.
  bedrock_au_foundation_model_arns = [
    "arn:aws:bedrock:ap-southeast-2::foundation-model/${local.bedrock_model_base}",
    "arn:aws:bedrock:ap-southeast-4::foundation-model/${local.bedrock_model_base}",
  ]

  bedrock_invoke_via_profile_resources = startswith(local.web.bedrock_model_id, "au.") ? local.bedrock_au_foundation_model_arns : [local.bedrock_foundation_model_arn]
}
