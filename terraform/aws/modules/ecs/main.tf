variable "project"                     { type = string }
variable "environment"                 { type = string }
variable "region"                      { type = string }
variable "vpc_id"                      { type = string }
variable "private_subnet_ids"          { type = list(string) }
variable "public_subnet_ids"           { type = list(string) }
variable "ecs_tasks_sg_id"             { type = string }
variable "frontend_tg_arn"             { type = string }
variable "backend_tg_arn"              { type = string }
variable "ecs_task_execution_role_arn" { type = string }
variable "ecs_task_role_arn"           { type = string }
variable "frontend_image"              { type = string }
variable "backend_image"               { type = string }
variable "backend_url"                 { type = string }
variable "frontend_cpu"                { type = number }
variable "frontend_memory"             { type = number }
variable "backend_cpu"                 { type = number }
variable "backend_memory"              { type = number }
variable "frontend_min_count"          { type = number }
variable "frontend_max_count"          { type = number }
variable "backend_min_count"           { type = number }
variable "backend_max_count"           { type = number }

resource "aws_ecs_cluster" "main" {
  name = "${var.project}-${var.environment}"
  setting {
    name  = "containerInsights"
    value = var.environment == "prod" ? "enabled" : "disabled"
  }
  tags = { Environment = var.environment }
}

resource "aws_cloudwatch_log_group" "frontend" {
  name              = "/ecs/${var.project}-${var.environment}/frontend"
  retention_in_days = var.environment == "prod" ? 30 : 7
}

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/ecs/${var.project}-${var.environment}/backend"
  retention_in_days = var.environment == "prod" ? 30 : 7
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.project}-${var.environment}-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.backend_cpu
  memory                   = var.backend_memory
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn

  container_definitions = jsonencode([{
    name      = "backend"
    image     = var.backend_image
    essential = true
    portMappings = [{ containerPort = 8000, protocol = "tcp" }]
    environment = [{ name = "ENVIRONMENT", value = var.environment }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.backend.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "backend"
      }
    }
  }])
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "${var.project}-${var.environment}-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.frontend_cpu
  memory                   = var.frontend_memory
  execution_role_arn       = var.ecs_task_execution_role_arn
  task_role_arn            = var.ecs_task_role_arn

  container_definitions = jsonencode([{
    name      = "frontend"
    image     = var.frontend_image
    essential = true
    portMappings = [{ containerPort = 3000, protocol = "tcp" }]
    environment = [
      { name = "NODE_ENV",            value = "production" },
      { name = "NEXT_PUBLIC_API_URL", value = var.backend_url }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.frontend.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "frontend"
      }
    }
  }])
}

resource "aws_ecs_service" "backend" {
  name            = "${var.project}-${var.environment}-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.backend_min_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.environment == "dev" ? var.public_subnet_ids : var.private_subnet_ids
    security_groups  = [var.ecs_tasks_sg_id]
    assign_public_ip = var.environment == "dev" ? true : false
  }

  load_balancer {
    target_group_arn = var.backend_tg_arn
    container_name   = "backend"
    container_port   = 8000
  }

  lifecycle { ignore_changes = [task_definition, desired_count] }
}

resource "aws_ecs_service" "frontend" {
  name            = "${var.project}-${var.environment}-frontend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = var.frontend_min_count
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.environment == "dev" ? var.public_subnet_ids : var.private_subnet_ids
    security_groups  = [var.ecs_tasks_sg_id]
    assign_public_ip = var.environment == "dev" ? true : false
  }

  load_balancer {
    target_group_arn = var.frontend_tg_arn
    container_name   = "frontend"
    container_port   = 3000
  }

  lifecycle { ignore_changes = [task_definition, desired_count] }
}

resource "aws_appautoscaling_target" "backend" {
  count              = var.environment == "dev" ? 0 : 1
  max_capacity       = var.backend_max_count
  min_capacity       = var.backend_min_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.backend.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "backend_cpu" {
  count              = var.environment == "dev" ? 0 : 1
  name               = "${var.project}-${var.environment}-backend-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.backend[0].resource_id
  scalable_dimension = aws_appautoscaling_target.backend[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.backend[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 70.0
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_target" "frontend" {
  count              = var.environment == "dev" ? 0 : 1
  max_capacity       = var.frontend_max_count
  min_capacity       = var.frontend_min_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.frontend.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "frontend_cpu" {
  count              = var.environment == "dev" ? 0 : 1
  name               = "${var.project}-${var.environment}-frontend-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.frontend[0].resource_id
  scalable_dimension = aws_appautoscaling_target.frontend[0].scalable_dimension
  service_namespace  = aws_appautoscaling_target.frontend[0].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 70.0
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

output "cluster_name"          { value = aws_ecs_cluster.main.name }
output "backend_service_name"  { value = aws_ecs_service.backend.name }
output "frontend_service_name" { value = aws_ecs_service.frontend.name }
