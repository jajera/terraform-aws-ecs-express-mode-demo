output "service_url" {
  description = "HTTPS endpoint URL for the public web service (requires access_type PUBLIC)"
  value       = aws_ecs_express_gateway_service.web.ingress_paths[0].endpoint
}

output "service_access_type" {
  description = "Ingress access type: PUBLIC (internet-facing) or PRIVATE (VPC-internal only)"
  value       = aws_ecs_express_gateway_service.web.ingress_paths[0].access_type
}

output "health_check_path" {
  description = "HTTP path the Express Mode load balancer uses for target health checks"
  value       = local.web.health_check_path
}

output "health_check_url" {
  description = "Full URL the Express Mode load balancer polls for target health checks"
  value       = "${aws_ecs_express_gateway_service.web.ingress_paths[0].endpoint}${local.web.health_check_path}"
}

output "web_ui_url" {
  description = "Swagger UI for the image analysis API (open in a browser; the root URL returns 404)"
  value       = "${aws_ecs_express_gateway_service.web.ingress_paths[0].endpoint}/docs"
}

output "cluster_name" {
  description = "Name of the ECS cluster hosting the web service"
  value       = aws_ecs_express_gateway_service.web.cluster
}

output "service_name" {
  description = "Name of the ECS Express Mode web service"
  value       = aws_ecs_express_gateway_service.web.service_name
}

output "container_image" {
  description = "Container image URI used by the web service"
  value       = local.web.container_image
}

output "bedrock_model_id" {
  description = "Bedrock model or inference profile ID configured on the container"
  value       = local.web.bedrock_model_id
}

output "bedrock_max_tokens" {
  description = "Maximum Bedrock response tokens configured on the container"
  value       = local.web.bedrock_max_tokens
}

output "vpc_id" {
  description = "VPC ID created for ECS Express networking"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs used by the web service and ALB"
  value       = aws_subnet.public[*].id
}
