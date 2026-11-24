# ECS Fargate Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-${var.environment}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# IAM Role: Task Execution (Pulls from ECR and reads Secrets Manager)
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.project_name}-${var.environment}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_standard" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "secrets_access" {
  name = "${var.project_name}-${var.environment}-secrets-access"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue"
      ]
      Resource = [
        aws_secretsmanager_secret.database_credentials.arn,
        aws_secretsmanager_secret.postgrest_jwt_secret.arn,
        aws_secretsmanager_secret.gateway_service_key.arn,
        aws_secretsmanager_secret.demo_routing.arn
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_secrets_access" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.secrets_access.arn
}

locals {
  ecs_subnet_ids = var.ecs_assign_public_ip ? var.public_subnet_ids : var.private_subnet_ids
}

# ECS Task Definition: Dual container pod (Gateway + PostgREST) over localhost
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-${var.environment}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = upper(var.ecs_cpu_architecture)
  }

  container_definitions = jsonencode([
    # 1. Auth Gateway Container (Port 3000)
    {
      name      = "auth-gateway"
      image     = var.gateway_image
      essential = true
      portMappings = [{
        containerPort = 3000
        hostPort      = 3000
      }]
      environment = [
        { name = "NODE_ENV", value = "production" },
        { name = "PORT", value = "3000" },
        { name = "APP_ENV", value = "production" },
        { name = "PGRST_URL", value = "http://127.0.0.1:3001" },
        { name = "FIREBASE_PROJECT_ID", value = var.firebase_project_id },
        { name = "DEMO_REAL_ROUTING_ENABLED", value = "1" },
        { name = "DEMO_PGRST_JWT_AUD", value = "authenticated" }
      ]
      secrets = [
        { name = "PGRST_JWT_SECRET", valueFrom = "${aws_secretsmanager_secret.postgrest_jwt_secret.arn}:jwt_secret::" },
        { name = "SERVICE_ROLE_KEY", valueFrom = "${aws_secretsmanager_secret.gateway_service_key.arn}:service_key::" },
        { name = "DEMO_FIREBASE_UID_ALLOWLIST", valueFrom = "${aws_secretsmanager_secret.demo_routing.arn}:DEMO_FIREBASE_UID_ALLOWLIST::" },
        { name = "DEMO_PGRST_URL", valueFrom = "${aws_secretsmanager_secret.demo_routing.arn}:DEMO_PGRST_URL::" },
        { name = "DEMO_PGRST_JWT_SECRET", valueFrom = "${aws_secretsmanager_secret.demo_routing.arn}:DEMO_PGRST_JWT_SECRET::" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "gateway"
        }
      }
    },
    # 2. PostgREST Official Container (Port 3001, private to the pod)
    {
      name      = "postgrest"
      image     = var.postgrest_image
      essential = true
      portMappings = [{
        containerPort = 3001
        hostPort      = 3001
      }]
      environment = [
        { name = "PGRST_SERVER_PORT", value = "3001" },
        { name = "PGRST_DB_SCHEMAS", value = "public" },
        { name = "PGRST_DB_ANON_ROLE", value = "anon" },
        { name = "PGRST_DB_POOL", value = "10" },
        { name = "PGRST_DB_MAX_ROWS", value = "1000" },
        { name = "PGRST_JWT_AUD", value = "authenticated" }
      ]
      secrets = [
        { name = "PGRST_DB_URI", valueFrom = "${aws_secretsmanager_secret.database_credentials.arn}:connection_string::" },
        { name = "PGRST_JWT_SECRET", valueFrom = "${aws_secretsmanager_secret.postgrest_jwt_secret.arn}:jwt_secret::" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "postgrest"
        }
      }
    }
  ])
}

# ECS Service: start at desired_count=0; scale after secrets + health check
resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-${var.environment}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = local.ecs_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = var.ecs_assign_public_ip
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.gateway.arn
    container_name   = "auth-gateway"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.https]

  lifecycle {
    ignore_changes = [desired_count]
  }
}
