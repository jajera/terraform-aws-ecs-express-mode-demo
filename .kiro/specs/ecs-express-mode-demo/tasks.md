# Implementation Plan: ECS Express Mode Demo

## Overview

This plan implements a Terraform demo project deploying an AI-powered image analysis API using AWS ECS Express Mode and Amazon Bedrock. The implementation follows a bottom-up approach: foundation files first (versions, providers, variables), then core infrastructure (IAM, ECR, ECS), the container application, automation scripts, CI workflows, workspace config, and finally documentation with tests.

## Tasks

- [x] 1. Set up Terraform foundation files
  - [x] 1.1 Create `versions.tf` with Terraform and provider version constraints
    - Define `terraform` block with `required_version = ">= 1.5.0"`
    - Define `required_providers` block with `aws` source `hashicorp/aws` version `">= 5.70.0"`
    - _Requirements: 1.1, 1.3_

  - [x] 1.2 Create `providers.tf` with AWS provider and default tags
    - Configure `aws` provider with `region = var.aws_region`
    - Add `default_tags` block with Project (from `var.project`), Environment (from `var.environment`), and ManagedBy ("Terraform")
    - _Requirements: 1.1, 1.4_

  - [x] 1.3 Create `variables.tf` with validated input variables
    - Define `project` variable (string, default "terraform-aws-ecs-express-mode-demo") with validation: lowercase alphanumeric + hyphens, 3-32 chars, starts with letter, no trailing hyphen
    - Define `environment` variable (string, default "dev") with validation: must be "dev", "staging", or "prod"
    - Define `aws_region` variable (string, default "us-east-1") with validation: matches AWS region pattern `[a-z]{2}-(north|south|east|west|central)-[0-9]`
    - Each validation block must include a descriptive `error_message` with a valid example
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5_

  - [x] 1.4 Create `data.tf` with data sources
    - Define `aws_caller_identity` data source for current account ID
    - Define `aws_region` data source for current region
    - _Requirements: 1.1_

  - [x] 1.5 Create `main.tf` with random suffix and local values
    - Define `random_string` resource for name uniqueness suffix
    - Define `locals` block with `name_prefix = "${var.project}-${random_string.suffix.result}"`
    - _Requirements: 1.1_

- [x] 2. Implement IAM roles and policies
  - [x] 2.1 Create `iam.tf` with Task Execution Role
    - Define `aws_iam_role` for task execution with trust policy for `ecs.amazonaws.com` service principal
    - Include `aws:SourceAccount` condition in trust policy
    - Attach inline policy for ECR image pull and CloudWatch Logs write permissions
    - _Requirements: 4.1, 4.4, 4.5_

  - [x] 2.2 Add Infrastructure Role to `iam.tf`
    - Define `aws_iam_role` for infrastructure with trust policy for `ecs.amazonaws.com` service principal
    - Include `aws:SourceAccount` condition in trust policy
    - Attach AWS managed policy required by ECS Express Mode for ALB, networking, and auto scaling provisioning
    - _Requirements: 4.2, 4.4, 4.5_

  - [x] 2.3 Add Bedrock Task Role to `iam.tf`
    - Define `aws_iam_role` for bedrock task with trust policy for `ecs-tasks.amazonaws.com` service principal
    - Include `aws:SourceAccount` condition in trust policy
    - Attach inline policy with `bedrock:InvokeModel` permission scoped to the specific model ARN
    - _Requirements: 4.3, 4.4, 4.5_

- [x] 3. Implement ECR repository and image build
  - [x] 3.1 Create `ecr.tf` with ECR repository
    - Define `aws_ecr_repository` with mutable image tag mutability and scan-on-push enabled
    - Define `aws_ecr_lifecycle_policy` to retain only the 5 most recent images
    - _Requirements: 5.1, 5.2, 5.4_

  - [x] 3.2 Add Docker build/push resource to `ecr.tf`
    - Define `null_resource` with `local-exec` provisioner to authenticate with ECR, build, tag as `latest`, and push
    - Configure `triggers` block referencing a content hash of the `app/` directory so rebuilds happen on source changes
    - _Requirements: 5.3, 5.5_

- [x] 4. Implement container application
  - [x] 4.1 Create `app/requirements.txt` with Python dependencies
    - Include fastapi, uvicorn, boto3, and pydantic
    - _Requirements: 3.1_

  - [x] 4.2 Create `app/main.py` with FastAPI application
    - Implement `GET /health` endpoint returning `{"status": "healthy"}` with HTTP 200
    - Implement `POST /analyze` endpoint accepting JSON body with `image_url` field (Pydantic `HttpUrl` validated)
    - On valid request, invoke Amazon Bedrock Claude model with the image URL and return `{"image_url": "...", "description": "..."}`
    - On Bedrock failure, catch exceptions and return HTTP 502 with `{"error": "Bedrock invocation failed: <message>"}`
    - On invalid/missing URL, return HTTP 422 with `{"error": "..."}` (handled by Pydantic validation)
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7_

  - [x] 4.3 Create `app/Dockerfile`
    - Use Python slim base image
    - Create non-root user and switch to it
    - Copy requirements.txt and install dependencies
    - Copy application code
    - Expose port 8000
    - Set CMD to run uvicorn on 0.0.0.0:8000
    - _Requirements: 3.5_

- [x] 5. Implement ECS cluster, task definition, and service
  - [x] 5.1 Create `ecs.tf` with ECS cluster resource
    - Define `aws_ecs_cluster` resource with name from `local.name_prefix`
    - _Requirements: 2.1_

  - [x] 5.2 Add ECS task definition to `ecs.tf`
    - Define `aws_ecs_task_definition` with Fargate compatibility, CPU 256, memory 512
    - Reference container image from ECR repository URL
    - Assign Task Execution Role and Bedrock Task Role
    - Configure container port mapping on port 8000
    - Configure awslogs log driver with CloudWatch log group
    - _Requirements: 2.5, 2.3_

  - [x] 5.3 Add ECS Express Mode service to `ecs.tf`
    - Define `aws_ecs_service` with Express Mode configuration
    - Configure `availability_zone_rebalancing` and `deployment_configuration` blocks
    - Reference task definition, cluster, and Infrastructure Role ARN
    - _Requirements: 2.2, 2.3, 2.4_

- [x] 6. Create outputs
  - [x] 6.1 Create `outputs.tf` with all output values
    - Output `service_url` - ECS Express Mode service HTTPS URL with description
    - Output `cluster_name` - ECS cluster name with description
    - Output `service_name` - ECS service name with description
    - Output `ecr_repository_url` - ECR repository URL with description
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 7.5_

- [x] 7. Checkpoint - Validate Terraform configuration
  - Ensure all tests pass, ask the user if questions arise.

- [x] 8. Create CI/CD workflows
  - [x] 8.1 Create `.github/workflows/commitmsg-conform.yml`
    - Define workflow triggered on `pull_request` events
    - Reference `actionsforge/actions/.github/workflows/commitmsg-conform.yml@main` reusable workflow
    - _Requirements: 8.1, 8.4, 8.5_

  - [x] 8.2 Create `.github/workflows/markdown-lint.yml`
    - Define workflow triggered on `push` and `pull_request` events
    - Reference `actionsforge/actions/.github/workflows/markdown-lint.yml@main` reusable workflow
    - _Requirements: 8.2, 8.4, 8.5_

  - [x] 8.3 Create `.github/workflows/terraform-lint-validate.yml`
    - Define workflow triggered on `push` and `pull_request` events
    - Reference `actionsforge/actions/.github/workflows/terraform-lint-validate.yml@main` reusable workflow
    - _Requirements: 8.3, 8.4, 8.5_

- [x] 9. Create VSCode workspace configuration
  - [x] 9.1 Create `.vscode/extensions.json` with recommended extensions
    - Include at least 5 extension identifiers: Terraform, Python, markdownlint, Prettier, shell-format
    - _Requirements: 9.1_

  - [x] 9.2 Create `.vscode/settings.json` with editor settings
    - Configure file associations, file exclude patterns, format-on-save
    - Set language-specific formatters for Terraform, Python, Markdown, and Shell
    - _Requirements: 9.2_

  - [x] 9.3 Create `.vscode/cspell.json` with project dictionary
    - Include at least 5 project-relevant terms covering Terraform, AWS, and ECS terminology
    - _Requirements: 9.3_

- [x] 10. Create automation script
  - [x] 10.1 Create `scripts/run.sh` with full lifecycle automation
    - Start with `#!/bin/bash` and `set -e`
    - Print progress messages before each step
    - Execute `terraform init`
    - Execute `terraform apply -auto-approve`
    - Retrieve service URL from `terraform output` and poll health endpoint (30 retries, 10s interval)
    - Execute `terraform destroy -auto-approve`
    - On failure, output error to stderr and exit non-zero
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5, 10.6, 10.7_

- [x] 11. Create steering files
  - [x] 11.1 Create `.kiro/steering/domain-context.md`
    - Document project domain context for AI assistants
    - _Requirements: 1.1_

  - [x] 11.2 Create `.kiro/steering/terraform-conventions.md`
    - Document Terraform coding conventions used in the project
    - _Requirements: 1.5_

- [x] 12. Create documentation
  - [x] 12.1 Create `README.md` with comprehensive documentation
    - Project description explaining ECS Express Mode and AI image analysis use case
    - Prerequisites section (AWS account, Terraform >= 1.5.0, Docker, AWS CLI, Bedrock model access)
    - Step-by-step usage instructions (configure, deploy, verify, destroy)
    - Project file structure section
    - Input variables and outputs in tabular format
    - Destroy/cleanup instructions section
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5, 11.6_

- [x] 13. Checkpoint - Ensure full project builds and validates
  - Ensure all tests pass, ask the user if questions arise.

- [x] 14. Implement tests
  - [x] 14.1 Create `tests/conftest.py` with shared test fixtures
    - Define mock Bedrock client fixture
    - Define FastAPI test client fixture
    - _Requirements: 3.1_

  - [x] 14.2 Write property test for analyze response format (Property 1)
    - **Property 1: Analyze response format invariant**
    - Generate valid URLs and mock Bedrock responses, verify response contains `image_url` and non-empty `description`
    - Use Hypothesis with minimum 100 examples
    - **Validates: Requirements 3.1, 3.3**

  - [x] 14.3 Write property test for Bedrock failure handling (Property 2)
    - **Property 2: Bedrock failure produces 502 error response**
    - Generate valid URLs with various mock exceptions, verify HTTP 502 with non-empty `error` field
    - Use Hypothesis with minimum 100 examples
    - **Validates: Requirements 3.6**

  - [x] 14.4 Write property test for invalid URL rejection (Property 3)
    - **Property 3: Invalid URL rejection produces 422**
    - Generate invalid URL strings, verify HTTP 422 with non-empty `error` field and no Bedrock invocation
    - Use Hypothesis with minimum 100 examples
    - **Validates: Requirements 3.7**

  - [x] 14.5 Write property test for project variable validation (Property 4)
    - **Property 4: Project variable validation accepts valid names and rejects invalid ones**
    - Generate strings matching/not matching project name constraints, verify regex validation logic
    - Use Hypothesis with minimum 100 examples
    - **Validates: Requirements 6.1**

  - [x] 14.6 Write property test for AWS region validation (Property 5)
    - **Property 5: AWS region variable validation accepts valid regions and rejects invalid patterns**
    - Generate strings matching/not matching region pattern, verify regex validation logic
    - Use Hypothesis with minimum 100 examples
    - **Validates: Requirements 6.3**

  - [x] 14.7 Write smoke tests for Terraform structure
    - Verify all required .tf files exist at root
    - Verify versions.tf has correct version constraints
    - Verify providers.tf has default_tags block
    - Verify iam.tf defines 3 separate IAM roles with condition blocks
    - Verify outputs.tf has all 4 outputs with descriptions
    - Verify CI workflows are in correct directory (3 files)
    - Verify run.sh has correct shebang and set -e
    - Verify README.md has required sections
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 4.4, 4.5, 7.1-7.5, 8.4, 8.5, 10.1, 11.1-11.6_

- [x] 15. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation
- Property tests validate universal correctness properties from the design document using Hypothesis (Python)
- Smoke tests verify Terraform file structure and content without requiring AWS credentials
- The implementation uses HCL for Terraform files and Python for the container application and tests
- All Terraform files use snake_case naming per Requirement 1.5

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "1.3", "1.4", "1.5"] },
    { "id": 1, "tasks": ["2.1", "2.2", "2.3", "4.1"] },
    { "id": 2, "tasks": ["3.1", "4.2", "4.3"] },
    { "id": 3, "tasks": ["3.2", "5.1"] },
    { "id": 4, "tasks": ["5.2", "5.3", "6.1"] },
    { "id": 5, "tasks": ["8.1", "8.2", "8.3", "9.1", "9.2", "9.3"] },
    { "id": 6, "tasks": ["10.1", "11.1", "11.2"] },
    { "id": 7, "tasks": ["12.1"] },
    { "id": 8, "tasks": ["14.1"] },
    { "id": 9, "tasks": ["14.2", "14.3", "14.4", "14.5", "14.6", "14.7"] }
  ]
}
```
