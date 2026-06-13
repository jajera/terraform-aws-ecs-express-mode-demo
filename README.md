# terraform-aws-ecs-express-mode-demo

Deploy an AI-powered image analysis API using AWS ECS Express Mode and Amazon Bedrock.

This Terraform project demonstrates how ECS Express Mode simplifies containerized
application deployment by automatically provisioning networking (VPC, subnets),
load balancing (ALB with HTTPS), auto scaling, and monitoring from minimal
configuration.

The container image is published to GitHub Container Registry:
[`ghcr.io/platformfuzz/bedrock-image-analyzer`](https://github.com/platformfuzz/bedrock-image-analyzer-image/pkgs/container/bedrock-image-analyzer).

Source and build pipeline:
[platformfuzz/bedrock-image-analyzer-image](https://github.com/platformfuzz/bedrock-image-analyzer-image).

## Prerequisites

- AWS account with appropriate permissions
- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with valid credentials
- Amazon Bedrock model access enabled for your chosen model in the target region (default: `au.anthropic.claude-sonnet-4-6` in `ap-southeast-2`)

## Usage

### 1. Configure variables

Review and optionally override the default variable values. You can create a
`terraform.tfvars` file or pass variables on the command line:

```hcl
project     = "ecs-express-mode-demo"
environment = "dev"
aws_region  = "ap-southeast-2"
vpc_cidr    = "10.42.0.0/16"
```

Service settings (container image, Bedrock model, health check path) live in `locals.tf` under `local.web`. The container reads `MODEL_ID` and `MAX_TOKENS` from the environment. Pick a model [available in your region](https://docs.aws.amazon.com/bedrock/latest/userguide/models-regions.html) and enable access in the Bedrock console.

**Inference profiles** (e.g. `au.anthropic.claude-sonnet-4-6` in `ap-southeast-2`) require a current `bedrock-image-analyzer` image that validates profiles via `get_inference_profile` at startup. Push an updated image to GHCR before `terraform apply`, or the ECS deployment can fail health checks and roll back.

### 2. Deploy

Run the full lifecycle using the automation script:

```bash
chmod +x scripts/run.sh
./scripts/run.sh
```

Or deploy manually step by step:

```bash
terraform init
terraform apply -auto-approve
```

### 3. Verify

Health checks in ECS Express Mode are performed by the **Application Load Balancer**,
not as a container-level check in the ECS task definition. The ECS **Tasks** tab may
show **Health status: Unknown** — that is expected. The ALB health check is
configured via `health_check_path` (default `/health`).

**Internet access:** Express Mode creates an **internet-facing** ALB only when tasks
use **public subnets**. Private subnets produce a **VPC-internal** endpoint
(`access_type = PRIVATE`) that cannot be reached from the public internet.

See [EXPRESS_MODE_NOTES.md](EXPRESS_MODE_NOTES.md) for limitations, IAM pitfalls,
health check behaviour, and other watchouts discovered while building
this demo.

After deployment, confirm the endpoint is internet-facing and reachable:

```bash
terraform output -raw service_access_type   # must be PUBLIC for browser access
curl "$(terraform output -raw health_check_url)"
```

Open the **Swagger UI** in a browser (the root URL returns 404 — that is expected):

```bash
terraform output -raw web_ui_url
# e.g. https://te-....ecs.ap-southeast-2.on.aws/docs
```

Test the image analysis API:

```bash
SERVICE_URL=$(terraform output -raw service_url)
```

```bash
curl -X POST "${SERVICE_URL}/analyze" \
  -H "Content-Type: application/json" \
  -d '{"image_url": "https://placehold.co/600x400/png"}'
```

Use a direct, publicly reachable image URL that allows **server-side GET** from AWS (must return `image/*`, not HTML). Some hosts (e.g. Wikimedia) return 403 to datacenter IPs — use `https://placehold.co/600x400/png` or similar for demos. If `/analyze` returns 503, the configured model in `locals.tf` is not available in `aws_region` — update `local.web.bedrock_model_id` and re-apply.

### 4. Destroy

Remove all deployed resources:

```bash
terraform destroy -auto-approve
```

## Project Structure

```text
.
├── scripts/
│   └── run.sh                              # Lifecycle automation (init → apply → verify → destroy)
├── .github/workflows/
│   ├── commitmsg-conform.yml               # Commit message convention enforcement
│   ├── markdown-lint.yml                    # Markdown linting
│   └── terraform-lint-validate.yml         # Terraform fmt and validate
├── data.tf                                 # Data sources (account ID, region, AZs)
├── ecs.tf                                  # ECS Express gateway service and CloudWatch logs
├── iam.tf                                  # Three IAM roles (task execution, infrastructure, bedrock)
├── vpc.tf                                  # VPC, public subnets, routing, web security group
├── main.tf                                 # Random suffix for resource naming
├── locals.tf                               # Service config (local.web) and Bedrock IAM locals
├── outputs.tf                              # Output values
├── providers.tf                            # AWS provider with default_tags
├── variables.tf                            # Validated input variables
├── versions.tf                             # Terraform and provider version constraints
├── EXPRESS_MODE_NOTES.md                   # Limitations, watchouts, and lessons learned
├── LICENSE                                 # MIT license
└── README.md                               # This file
```

> **Note:** The container image is pulled from
> `ghcr.io/platformfuzz/bedrock-image-analyzer`. Source and build details are in
> [platformfuzz/bedrock-image-analyzer-image](https://github.com/platformfuzz/bedrock-image-analyzer-image).

## Input Variables

| Name | Type | Default | Description |
| ---- | ---- | ------- | ----------- |
| `project` | string | `"ecs-express-mode-demo"` | Project name used for resource naming and tagging |
| `environment` | string | `"dev"` | Deployment environment (dev, staging, or prod) |
| `aws_region` | string | `"ap-southeast-2"` | AWS region for resource deployment |
| `vpc_cidr` | string | `"10.42.0.0/16"` | CIDR block for the VPC created by this project |

Web service settings (`container_image`, `bedrock_model_id`, `bedrock_max_tokens`, ports) are defined in `locals.tf` as `local.web`.

## Outputs

| Name | Description |
| ---- | ----------- |
| `health_check_path` | ALB target group health check path (default `/health`) |
| `health_check_url` | Full URL the ALB polls for target health |
| `service_access_type` | `PUBLIC` (internet-facing) or `PRIVATE` (VPC-internal only) |
| `service_url` | HTTPS base URL for the ECS Express Mode service |
| `web_ui_url` | Swagger UI URL (`/docs`) — open this in a browser |
| `cluster_name` | Name of the ECS cluster hosting the Express Mode service |
| `service_name` | Name of the ECS Express Mode service |
| `container_image` | Container image URI used by the ECS Express service |
| `bedrock_model_id` | Bedrock model or inference profile configured on the container |
| `bedrock_max_tokens` | Max Bedrock response tokens configured on the container |
| `vpc_id` | VPC ID created for ECS Express networking |
| `public_subnet_ids` | Public subnet IDs used by the ECS Express service and ALB |

## Cleanup

To destroy all resources created by this project:

```bash
terraform destroy -auto-approve
```

The automation script (`scripts/run.sh`) includes a destroy step at the end of
its lifecycle. If you deployed using the script, resources are already cleaned up.

To manually verify no resources remain:

```bash
terraform state list
```

If the state file shows no resources, all infrastructure has been removed.
