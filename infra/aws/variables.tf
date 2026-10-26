variable "aws_region" {
  type        = string
  description = "AWS region for deployment"
  default     = "ap-south-1"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "production"
}

variable "project_name" {
  type        = string
  description = "Project name tag"
  default     = "doctornect"
}

variable "vpc_id" {
  type        = string
  description = "Target VPC ID"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs across at least 2 AZs for ALB. Expected as existing inputs, not created by this module."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs across at least 2 AZs for ECS tasks. NOTE: Private subnets and NAT Gateways are expected as existing inputs, not created by this module. The route tables for these subnets MUST have a 0.0.0.0/0 route pointing to a functional NAT Gateway. If the VPC has no NAT Gateway, ECS tasks in private subnets cannot reach the internet, causing outbound HTTPS (port 443) requests to Google JWKS (https://www.googleapis.com) to hang and time out, resulting in HTTP 504 Gateway Timeouts on all authenticated requests."
}

variable "domain_name" {
  type        = string
  description = "API domain name (e.g. api.doctornect.com)"
  default     = "api.doctornect.com"
}

variable "acm_certificate_arn" {
  type        = string
  description = "ACM Certificate ARN for the HTTPS listener"
}

variable "gateway_image" {
  type        = string
  description = "ECR Image URI for the DoctorNect Auth Gateway container"
}

variable "postgrest_image" {
  type        = string
  description = "PostgREST official container image"
  default     = "postgrest/postgrest:v12.2.0"
}

variable "rds_endpoint" {
  type        = string
  description = "Amazon RDS PostgreSQL endpoint (hostname)"
}

variable "rds_port" {
  type        = number
  description = "RDS PostgreSQL port"
  default     = 5432
}

variable "rds_db_name" {
  type        = string
  description = "RDS PostgreSQL database name"
  default     = "doctornect"
}

variable "rds_security_group_id" {
  type        = string
  description = "Security Group ID of the RDS PostgreSQL instance"
}

variable "firebase_project_id" {
  type        = string
  description = "Firebase Project ID for token verification"
  default     = "medibond-45fad"
}
