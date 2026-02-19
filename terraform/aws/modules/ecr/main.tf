variable "project"     { type = string }
variable "environment" { type = string }

resource "aws_ecr_repository" "frontend" {
  name                 = "${var.project}-${var.environment}-frontend"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  tags = { Environment = var.environment }
}

resource "aws_ecr_repository" "backend" {
  name                 = "${var.project}-${var.environment}-backend"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
  tags = { Environment = var.environment }
}

resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 5 }
      action       = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 5 }
      action       = { type = "expire" }
    }]
  })
}

output "frontend_repo_url" { value = aws_ecr_repository.frontend.repository_url }
output "backend_repo_url"  { value = aws_ecr_repository.backend.repository_url }
