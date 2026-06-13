variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "ecs-express-mode-demo"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,48}[a-z0-9]$", var.project))
    error_message = "Project name must contain only lowercase alphanumeric characters and hyphens, start with a letter, not end with a hyphen, and be 3-50 characters. Example: my-demo-project"
  }
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod. Example: dev"
  }
}

variable "aws_region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "ap-southeast-2"

  validation {
    condition     = can(regex("^[a-z]{2}-((north|south)(east|west)?|east|west|central)-[0-9]+$", var.aws_region))
    error_message = "AWS region must match the pattern like ap-southeast-2, us-east-1, eu-west-2. Example: ap-southeast-2"
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC created by this project"
  type        = string
  default     = "10.42.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block. Example: 10.42.0.0/16"
  }
}
