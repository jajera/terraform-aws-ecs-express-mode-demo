# Requirements Document

## Introduction

This feature creates a Terraform demo project that deploys an AI-powered image analysis API using AWS ECS Express Mode and Amazon Bedrock. The project demonstrates how ECS Express Mode simplifies containerized application deployment by automatically provisioning networking, load balancing, auto scaling, and monitoring infrastructure. The container application exposes a REST API (built with Python/FastAPI) that accepts image URLs and returns AI-generated descriptions and analysis using Amazon Bedrock's Claude model.

## Glossary

- **ECS_Express_Mode**: AWS ECS deployment mode that automatically provisions Fargate-based services with unique URLs, ALB with SSL/TLS, auto scaling, monitoring, and networking from minimal configuration (container image, task execution role, infrastructure role)
- **Terraform_Project**: The set of `.tf` files in the repository root that define AWS infrastructure as code
- **Container_Application**: A Python FastAPI application packaged as a Docker container that provides AI image analysis endpoints via Amazon Bedrock
- **Task_Execution_Role**: An IAM role that grants Amazon ECS permissions to pull container images and write logs
- **Infrastructure_Role**: An IAM role that grants ECS Express Mode permissions to provision supporting infrastructure (ALB, networking, auto scaling)
- **Bedrock_Task_Role**: An IAM role attached to the ECS task that grants the container application permissions to invoke Amazon Bedrock models
- **CI_Workflows**: GitHub Actions workflow files that enforce commit message conventions, markdown linting, and Terraform linting/validation
- **Default_Tags**: A standard set of resource tags (Project, Environment, ManagedBy) applied to all AWS resources via the AWS provider default_tags block
- **Run_Script**: A shell script (`run.sh`) that automates Terraform init, apply, verification, and destroy lifecycle

## Requirements

### Requirement 1: Terraform Project Structure

**User Story:** As a developer, I want the Terraform project to follow a flat file structure with consistent naming conventions, so that the project is easy to navigate and maintain.

#### Acceptance Criteria

1. THE Terraform_Project SHALL contain the following files in the repository root: `versions.tf`, `providers.tf`, `main.tf`, `variables.tf`, `outputs.tf`, and `data.tf`
2. THE Terraform_Project SHALL group related resources into dedicated files: `ecs.tf` for ECS Express Mode service and task definition, `iam.tf` for IAM roles and policies, and `ecr.tf` for the ECR repository and image build resources
3. THE Terraform_Project SHALL define the required Terraform version constraint using `>= 1.5.0` and the AWS provider version constraint using `>= 5.70.0` in `versions.tf`
4. THE Terraform_Project SHALL configure the AWS provider with a default_tags block containing Project (sourced from the project variable), Environment (sourced from the environment variable), and ManagedBy (set to literal value "Terraform") tags in `providers.tf`
5. THE Terraform_Project SHALL use snake_case naming for all `.tf` files in the repository root

### Requirement 2: ECS Express Mode Deployment

**User Story:** As a developer, I want to deploy a containerized application using ECS Express Mode, so that I can demonstrate simplified container deployment with minimal configuration.

#### Acceptance Criteria

1. THE Terraform_Project SHALL define an `aws_ecs_cluster` resource to host the Express Mode service
2. THE Terraform_Project SHALL define an `aws_ecs_service` resource configured with the `availability_zone_rebalancing` and `deployment_configuration` blocks appropriate for Express Mode deployment
3. THE Terraform_Project SHALL specify the container image URI from the ECR repository, Task_Execution_Role ARN, and Infrastructure_Role ARN as inputs for the ECS Express Mode service
4. WHEN the ECS service is deployed, THE ECS_Express_Mode SHALL automatically provision a Fargate-based service with a unique HTTPS URL accessible from the internet
5. THE Terraform_Project SHALL define an `aws_ecs_task_definition` resource that references the container image from the ECR repository and specifies CPU, memory, and container port configuration

### Requirement 3: Container Application

**User Story:** As a developer, I want a Python FastAPI application that provides AI image analysis, so that the demo showcases a modern AI-powered use case.

#### Acceptance Criteria

1. THE Container_Application SHALL expose a POST endpoint at `/analyze` that accepts a JSON request body containing a single image URL field
2. WHEN the Container_Application receives a valid image URL at the `/analyze` endpoint, THE Container_Application SHALL invoke the Amazon Bedrock Claude model to generate an image description
3. WHEN the Amazon Bedrock invocation completes successfully, THE Container_Application SHALL return a JSON response containing at minimum the image URL and the AI-generated description text
4. THE Container_Application SHALL expose a GET endpoint at `/health` that returns a JSON response with a status field indicating healthy when the application is running and able to accept requests
5. THE Container_Application SHALL include a Dockerfile that builds a container image using a non-root user, exposing a single port, and containing only runtime dependencies
6. IF the Amazon Bedrock invocation fails, THEN THE Container_Application SHALL return a JSON error response with an error message indicating the nature of the failure and HTTP status code 502
7. IF the image URL in the request is missing or not a valid URL format, THEN THE Container_Application SHALL return a JSON error response with an error message indicating the validation failure and HTTP status code 422

### Requirement 4: IAM Roles and Permissions

**User Story:** As a developer, I want per-resource IAM roles with least privilege permissions, so that the demo follows AWS security best practices.

#### Acceptance Criteria

1. THE Terraform_Project SHALL define a Task_Execution_Role with a trust policy for the `ecs.amazonaws.com` service principal and permissions limited to pulling images from the project's ECR repository and writing CloudWatch logs
2. THE Terraform_Project SHALL define an Infrastructure_Role with a trust policy for the `ecs.amazonaws.com` service principal and the AWS managed policy required by ECS Express Mode to provision ALB, networking, and auto scaling resources
3. THE Terraform_Project SHALL define a Bedrock_Task_Role with a trust policy for the `ecs-tasks.amazonaws.com` service principal, attached to the ECS task definition, with permissions limited to invoking the Bedrock model referenced by the Container_Application
4. THE Terraform_Project SHALL use separate IAM role resources for each of the three roles (Task_Execution_Role, Infrastructure_Role, Bedrock_Task_Role) ensuring no shared policy documents between them
5. THE Terraform_Project SHALL include IAM trust policy condition blocks using `aws:SourceAccount` or `aws:SourceArn` conditions to restrict role assumption to resources within the deploying AWS account

### Requirement 5: ECR Repository and Image Management

**User Story:** As a developer, I want an ECR repository to store the container image, so that ECS can pull the application image from a private registry.

#### Acceptance Criteria

1. THE Terraform_Project SHALL create an ECR repository for the container application image with image tag mutability set to mutable
2. THE Terraform_Project SHALL configure the ECR repository with image scanning on push enabled
3. THE Terraform_Project SHALL use a `null_resource` or `terraform_data` resource with a local-exec provisioner to authenticate with ECR, build the Docker image, tag it as `latest`, and push it to the ECR repository
4. THE Terraform_Project SHALL configure the ECR repository lifecycle policy to retain only the 5 most recent images and expire older untagged images
5. THE Terraform_Project SHALL define a triggers block on the build resource that references a source content hash so the image is rebuilt when application files change

### Requirement 6: Variables and Validation

**User Story:** As a developer, I want input variables with validation blocks, so that the Terraform configuration catches invalid inputs before deployment.

#### Acceptance Criteria

1. THE Terraform_Project SHALL define a `project` variable with a validation block that enforces the value contains only lowercase alphanumeric characters and hyphens, starts with a letter, does not end with a hyphen, and is between 3 and 32 characters in length
2. THE Terraform_Project SHALL define an `environment` variable with a validation block that restricts values to exactly one of the following: "dev", "staging", or "prod"
3. THE Terraform_Project SHALL define an `aws_region` variable with a validation block that enforces the value matches the pattern of 2 lowercase letters followed by a hyphen, a cardinal direction (north, south, east, west, central), a hyphen, and a single digit (e.g., "us-east-1", "eu-west-2")
4. THE Terraform_Project SHALL include an error_message string in each validation block that states the constraint being violated and provides an example of a valid value
5. IF an input variable value fails its validation block, THEN THE Terraform_Project SHALL reject the value during `terraform plan` or `terraform apply` before any infrastructure changes are made

### Requirement 7: Outputs

**User Story:** As a developer, I want Terraform outputs that display key resource identifiers and access URLs, so that I can verify the deployment and access the application.

#### Acceptance Criteria

1. THE Terraform_Project SHALL output the ECS Express Mode service URL for accessing the deployed application with a description attribute explaining its purpose
2. THE Terraform_Project SHALL output the ECS cluster name with a description attribute
3. THE Terraform_Project SHALL output the ECS service name with a description attribute
4. THE Terraform_Project SHALL output the ECR repository URL with a description attribute
5. THE Terraform_Project SHALL define all outputs in `outputs.tf`

### Requirement 8: CI/CD Workflows

**User Story:** As a developer, I want GitHub Actions workflows for linting and validation, so that code quality is enforced on every pull request.

#### Acceptance Criteria

1. THE CI_Workflows SHALL include a commit message conformance check workflow that triggers on `pull_request` events and references the `actionsforge/actions/.github/workflows/commitmsg-conform.yml@main` reusable workflow
2. THE CI_Workflows SHALL include a markdown linting workflow that triggers on `push` and `pull_request` events and references the `actionsforge/actions/.github/workflows/markdown-lint.yml@main` reusable workflow
3. THE CI_Workflows SHALL include a Terraform lint and validate workflow that triggers on `push` and `pull_request` events and references the `actionsforge/actions/.github/workflows/terraform-lint-validate.yml@main` reusable workflow
4. THE CI_Workflows SHALL be located in the `.github/workflows/` directory
5. THE CI_Workflows SHALL contain exactly 3 workflow files, one for each check (commit message conformance, markdown linting, Terraform lint and validate)

### Requirement 9: VSCode Workspace Configuration

**User Story:** As a developer, I want pre-configured VSCode settings and recommended extensions, so that contributors have a consistent development experience.

#### Acceptance Criteria

1. THE Terraform_Project SHALL include a `.vscode/extensions.json` file containing a "recommendations" array with at least 5 extension identifiers in `publisher.extension` format, including extensions for Terraform, Python, markdownlint, Prettier, and shell-format
2. THE Terraform_Project SHALL include a `.vscode/settings.json` file containing editor settings that cover file associations, file exclude patterns, format-on-save behavior, and language-specific formatter assignments for Terraform, Python, Markdown, and Shell files
3. THE Terraform_Project SHALL include a `.vscode/cspell.json` file containing a "words" array with at least 5 project-relevant dictionary terms covering Terraform, AWS, and ECS terminology used in the repository

### Requirement 10: Automation Script

**User Story:** As a developer, I want a shell script that automates the full Terraform lifecycle, so that I can quickly deploy, verify, and tear down the demo.

#### Acceptance Criteria

1. THE Run_Script SHALL be located at `scripts/run.sh` and begin with `#!/bin/bash` and `set -e` to ensure immediate exit on any command failure
2. THE Run_Script SHALL execute `terraform init` to initialize the Terraform working directory
3. THE Run_Script SHALL execute `terraform apply -auto-approve` to deploy all resources
4. THE Run_Script SHALL verify the deployment by retrieving the service URL from `terraform output` and polling the health endpoint until it receives an HTTP 200 response, retrying up to 30 times at 10-second intervals
5. THE Run_Script SHALL execute `terraform destroy -auto-approve` to remove all resources
6. IF any step in the Run_Script fails, THEN THE Run_Script SHALL output an error message to stderr and exit with a non-zero status code
7. THE Run_Script SHALL print a progress message to stdout before each lifecycle step (init, apply, verify, destroy)

### Requirement 11: Documentation

**User Story:** As a developer, I want comprehensive README documentation, so that users understand the project purpose, architecture, and how to use it.

#### Acceptance Criteria

1. THE Terraform_Project SHALL include a README.md with a project description explaining ECS Express Mode and the AI image analysis use case
2. THE Terraform_Project SHALL include a README.md section documenting prerequisites including AWS account, Terraform version, Docker, AWS CLI, and Bedrock model access enablement
3. THE Terraform_Project SHALL include a README.md section with step-by-step usage instructions covering at minimum: configure variables, deploy, verify, and destroy
4. THE Terraform_Project SHALL include a README.md section documenting the project file structure
5. THE Terraform_Project SHALL include a README.md section documenting input variables and outputs in tabular format
6. THE Terraform_Project SHALL include a README.md section documenting destroy/cleanup instructions
