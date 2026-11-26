# ECR repositories for the two gateway images.
# If a repository already exists in AWS (created by hand earlier), import it once instead of
# creating it again:
#   terraform import aws_ecr_repository.auth_gateway doctornect-auth-gateway
#   terraform import aws_ecr_repository.postgrest doctornect-postgrest
# Tags are immutable: every build gets a new tag (scripts: infra/aws/build_push_images.ps1).

locals {
  ecr_repositories = {
    auth_gateway = "${var.project_name}-auth-gateway"
    postgrest    = "${var.project_name}-postgrest"
  }
}

resource "aws_ecr_repository" "auth_gateway" {
  name                 = local.ecr_repositories.auth_gateway
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_repository" "postgrest" {
  name                 = local.ecr_repositories.postgrest
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Keep the last 20 images per repository; older ones are deleted automatically.
resource "aws_ecr_lifecycle_policy" "keep_recent" {
  for_each   = { auth_gateway = aws_ecr_repository.auth_gateway.name, postgrest = aws_ecr_repository.postgrest.name }
  repository = each.value

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 20 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}
