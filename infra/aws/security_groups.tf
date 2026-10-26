# ALB Security Group: Inbound HTTPS (443) from authorized internet clients
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-${var.environment}-alb-sg-"
  description = "Controls inbound traffic to DoctorNect Application Load Balancer"
  vpc_id      = var.vpc_id

  ingress {
    description = "Inbound HTTPS from Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Forward to ECS Tasks"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-sg"
  }
}

# ECS Security Group: Inbound HTTP (3000) from ALB only; Egress strictly 443 (HTTPS) and 5432 (RDS only)
resource "aws_security_group" "ecs" {
  name_prefix = "${var.project_name}-${var.environment}-ecs-sg-"
  description = "Isolates DoctorNect ECS Fargate Tasks (Egress: 443 to Web/NAT, 5432 to RDS SG only)"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Inbound from ALB only"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Outbound HTTPS (443) to Google JWKS, AWS Secrets Manager, ECR, and CloudWatch via NAT/VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description     = "Outbound PostgreSQL (5432) strictly to RDS Security Group only"
    from_port       = var.rds_port
    to_port         = var.rds_port
    protocol        = "tcp"
    security_groups = [var.rds_security_group_id]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-ecs-sg"
  }
}

# RDS Ingress Rule: Allow 5432 strictly from ECS Security Group (Never 0.0.0.0/0)
resource "aws_security_group_rule" "rds_ingress_from_ecs" {
  type                     = "ingress"
  description              = "Allow PostgreSQL inbound from ECS tasks only"
  from_port                = var.rds_port
  to_port                  = var.rds_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
  security_group_id        = var.rds_security_group_id
}
