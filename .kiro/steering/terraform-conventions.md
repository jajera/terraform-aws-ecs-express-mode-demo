# Terraform Conventions

This document describes the Terraform coding conventions used in this project. Follow these patterns when adding or modifying infrastructure code.

## File Naming

All `.tf` files use snake_case naming in the repository root:

- `versions.tf` — Terraform and provider version constraints
- `providers.tf` — AWS provider configuration with default tags
- `variables.tf` — Input variables with validation blocks
- `data.tf` — Data sources (aws_caller_identity, aws_region, aws_availability_zones)
- `locals.tf` — All local values (name_prefix, default_tags, web config, Bedrock ARNs)
- `main.tf` — Random suffix resource
- `ecs.tf` — ECS cluster, log group, and Express Gateway Service
- `iam.tf` — All IAM roles and policies
- `vpc.tf` — VPC, subnets, internet gateway, route table, security group
- `outputs.tf` — All output values

## Project Structure

- Flat layout with no modules — all resources live in the repository root
- Related resources are grouped in dedicated files (e.g., all IAM in `iam.tf`, all VPC in `vpc.tf`)
- No nested directories for Terraform code

## Resource Naming

Use `local.name_prefix` for consistent naming across all resources:

```hcl
locals {
  name_prefix = "${var.project}-${random_string.suffix.result}"
}
```

Resource names follow the pattern `${local.name_prefix}-<purpose>`, for example:

- `${local.name_prefix}-task-execution`
- `${local.name_prefix}-infrastructure`
- `${local.name_prefix}-bedrock-task`
- `${local.name_prefix}-web`
- `${local.name_prefix}-vpc`

## Locals Conventions

All local values live in `locals.tf`. Group related values:

```hcl
locals {
  name_prefix  = "..."
  default_tags = { ... }

  web = {
    container_image    = "..."
    container_port     = 8000
    health_check_path  = "/health"
    bedrock_model_id   = "..."
    bedrock_max_tokens = 1024
  }
}
```

- Use a map (`local.web`) to group container/service configuration
- Derive Bedrock ARNs dynamically based on model ID prefix
- Keep `default_tags` as a local referenced by the provider

## Variable Conventions

Every variable must include:

```hcl
variable "example" {
  description = "Human-readable description of the variable"
  type        = string
  default     = "sensible-default"

  validation {
    condition     = <boolean expression>
    error_message = "Constraint description with a valid example. Example: valid-value"
  }
}
```

- Always provide a `description`
- Always specify `type`
- Always include a `default` value
- Include a `validation` block with a descriptive `error_message` when constraints apply

## Provider Configuration

Configure the AWS provider with `default_tags` sourced from locals:

```hcl
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.default_tags
  }
}
```

Required tags on all resources:

- **Project** — sourced from `var.project`
- **Environment** — sourced from `var.environment`
- **ManagedBy** — literal value `"Terraform"`

## IAM Roles

- Define separate IAM roles per service (task execution, infrastructure, bedrock task)
- No shared policy documents between roles
- Always include trust policy conditions using `aws:SourceAccount`:

```hcl
Condition = {
  StringEquals = {
    "aws:SourceAccount" = data.aws_caller_identity.current.account_id
  }
}
```

- Use `aws_iam_role_policy_attachment` for AWS managed policies
- Use `aws_iam_role_policy` (inline) for custom permissions (e.g., Bedrock invoke)
- Add a comment above each role explaining its purpose

## Version Constraints

In `versions.tf`, use `>=` for provider version constraints:

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.50.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }
}
```

## ECS Express Mode

Use `aws_ecs_express_gateway_service` (not `aws_ecs_service`):

- Provide `cluster`, `service_name`, `execution_role_arn`, `infrastructure_role_arn`, `task_role_arn`
- Configure `primary_container` block with image, port, log config, and environment variables
- Configure `network_configuration` with explicit subnets and security groups
- Configure `scaling_target` for auto scaling
- Use `depends_on` to ensure VPC routing and IAM are ready before service creation

## Formatting

- Use `terraform fmt` standard formatting (2-space indentation, aligned `=` signs)
- Use `jsonencode()` for inline JSON policies instead of heredoc strings
- Use descriptive resource labels (e.g., `aws_iam_role.task_execution`, not `aws_iam_role.role1`)
