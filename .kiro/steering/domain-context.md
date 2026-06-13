# Domain Context

## Project Purpose

This is a Terraform demo project that deploys an AI-powered image analysis API using AWS ECS Express Mode (Express Gateway Services) and Amazon Bedrock. It demonstrates how ECS Express Mode simplifies containerized application deployment by automatically provisioning load balancing (ALB with HTTPS), auto scaling, and monitoring from minimal configuration.

## Key AWS Services

- **ECS Express Mode** (`aws_ecs_express_gateway_service`) — Deploys Fargate-based services with auto-provisioned ALB, TLS, auto scaling, and monitoring. Requires a VPC/subnets, container image, execution role, and infrastructure role.
- **Amazon Bedrock** — Provides Claude models (including regional inference profiles like `au.anthropic.claude-sonnet-4-6`) for AI image analysis invoked by the container application.
- **IAM** — Three separate least-privilege roles: task execution (logs + image pull via managed policy), infrastructure (ECS Express Mode provisioning), and task role (Bedrock invoke).
- **VPC** — Explicitly created with public subnets, internet gateway, and security group for the Express Mode service.
- **CloudWatch Logs** — Receives container logs via the awslogs log driver.

## Architecture Overview

```text
User → ALB (provisioned by ECS Express Mode) → ECS Fargate Task → Container → Amazon Bedrock
```

The Terraform configuration defines a VPC, ECS cluster, and Express Gateway Service. ECS Express Mode handles the ALB, TLS, auto scaling, and monitoring. The container runs a FastAPI app that accepts image URLs and returns AI-generated descriptions.

## Container Application

The container image is published to GitHub Container Registry at `ghcr.io/platformfuzz/bedrock-image-analyzer` and maintained in a separate repository: [platformfuzz/bedrock-image-analyzer-image](https://github.com/platformfuzz/bedrock-image-analyzer-image).

The app exposes:

- **POST /analyze** — Accepts `{"image_url": "https://..."}`, invokes Bedrock to describe the image
- **GET /health** — Returns `{"status": "healthy"}` for ALB health checks
- **GET /docs** — Swagger UI

## Key Concepts

- **ECS Express Gateway Service** (`aws_ecs_express_gateway_service`) is the Terraform resource that implements Express Mode — it auto-provisions ALB with HTTPS, auto scaling, and monitoring
- **Explicit VPC** — The project creates its own VPC, subnets, IGW, route table, and security group
- **Bedrock inference profiles** — The IAM policy dynamically handles both direct model ARNs and regional inference profile ARNs (e.g., `au.anthropic.claude-sonnet-4-6`)
- **Flat Terraform layout** — Each concern gets its own file at the repository root
- **Default tags** — All resources receive Project, Environment, and ManagedBy tags via `local.default_tags`
- **Input validation** — Variables include `validation` blocks with regex patterns

## File Structure

```text
.
├── scripts/
│   └── run.sh             # Lifecycle automation (init → apply → verify → destroy)
├── tests/                 # Property-based and smoke tests
├── data.tf                # Data sources (account ID, region, AZs)
├── ecs.tf                 # ECS cluster, log group, Express Gateway Service
├── iam.tf                 # Three IAM roles with least-privilege policies
├── locals.tf              # All local values (name_prefix, tags, web config, Bedrock ARNs)
├── main.tf                # Random suffix resource
├── outputs.tf             # Service URL, health check, cluster/service names, VPC info
├── providers.tf           # AWS provider with default_tags from locals
├── variables.tf           # Validated input variables (project, environment, aws_region, vpc_cidr)
├── versions.tf            # Terraform >= 1.5.0, AWS provider >= 6.50.0
└── vpc.tf                 # VPC, subnets, IGW, route table, security group
```

## Conventions

- All `.tf` files use **snake_case** naming
- HCL for infrastructure, Python for tests
- Terraform >= 1.5.0, AWS provider >= 6.50.0
- IAM roles use `aws:SourceAccount` conditions to restrict role assumption
- Container image is defined in `locals.tf`, not as a variable
- Bedrock model ID is configurable in locals with automatic inference profile detection
