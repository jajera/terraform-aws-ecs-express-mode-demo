resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/${local.name_prefix}-web"
  retention_in_days = 1
  skip_destroy      = false
}

resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-cluster"
}

resource "aws_ecs_express_gateway_service" "web" {
  cluster                 = aws_ecs_cluster.this.name
  service_name            = "${local.name_prefix}-web"
  execution_role_arn      = aws_iam_role.task_execution.arn
  infrastructure_role_arn = aws_iam_role.infrastructure.arn
  task_role_arn           = aws_iam_role.bedrock_task.arn
  # ALB target group health check path (Express Mode does not support ECS container healthCheck)
  health_check_path     = local.web.health_check_path
  cpu                   = "256"
  memory                = "512"
  wait_for_steady_state = true

  primary_container {
    image          = local.web.container_image
    container_port = local.web.container_port

    aws_logs_configuration {
      log_group         = aws_cloudwatch_log_group.web.name
      log_stream_prefix = "ecs"
    }

    environment {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment {
      name  = "MODEL_ID"
      value = local.web.bedrock_model_id
    }

    environment {
      name  = "MAX_TOKENS"
      value = tostring(local.web.bedrock_max_tokens)
    }
  }

  network_configuration {
    subnets         = aws_subnet.public[*].id
    security_groups = [aws_security_group.web.id]
  }

  scaling_target {
    auto_scaling_metric       = "AVERAGE_CPU"
    auto_scaling_target_value = 70
    min_task_count            = 1
    max_task_count            = 2
  }

  depends_on = [
    aws_ecs_cluster.this,
    aws_route_table_association.public,
    aws_vpc_security_group_ingress_rule.web_from_vpc,
    aws_iam_role_policy_attachment.task_execution,
    aws_iam_role_policy_attachment.infrastructure,
  ]
}
