terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket  = "devops-assignment-tfstate-380652644852"
    key     = "devops-assignment/aws/dev/terraform.tfstate"
    region  = "ap-south-1"
    encrypt = true
  }
}

provider "aws" {
  region = "ap-south-1"
  default_tags {
    tags = {
      Project     = "devops-assignment"
      Environment = "dev"
      ManagedBy   = "Terraform"
    }
  }
}

locals {
  project     = "devops-assignment"
  environment = "dev"
  region      = "ap-south-1"
}

module "networking" {
  source      = "../../modules/networking"
  project     = local.project
  environment = local.environment
  region      = local.region
  vpc_cidr    = "10.0.0.0/16"
}

module "ecr" {
  source      = "../../modules/ecr"
  project     = local.project
  environment = local.environment
}

module "iam" {
  source      = "../../modules/iam"
  project     = local.project
  environment = local.environment
}

module "alb" {
  source            = "../../modules/alb"
  project           = local.project
  environment       = local.environment
  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.public_subnet_ids
}

module "ecs" {
  source      = "../../modules/ecs"
  project     = local.project
  environment = local.environment
  region      = local.region

  # From networking module
  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids

  # From alb module
  ecs_tasks_sg_id = module.alb.ecs_tasks_sg_id
  frontend_tg_arn = module.alb.frontend_tg_arn
  backend_tg_arn  = module.alb.backend_tg_arn

  # From iam module
  ecs_task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  ecs_task_role_arn           = module.iam.ecs_task_role_arn

  # Placeholder images — CI/CD will update these
  frontend_image = "${module.ecr.frontend_repo_url}:latest"
  backend_image  = "${module.ecr.backend_repo_url}:latest"
  backend_url    = "http://${module.alb.alb_dns_name}"

  # DEV: minimal resources, no autoscaling
  frontend_cpu       = 256
  frontend_memory    = 512
  backend_cpu        = 256
  backend_memory     = 512
  frontend_min_count = 1
  frontend_max_count = 1
  backend_min_count  = 1
  backend_max_count  = 1
}

output "alb_url"          { value = "http://${module.alb.alb_dns_name}" }
output "frontend_ecr_url" { value = module.ecr.frontend_repo_url }
output "backend_ecr_url"  { value = module.ecr.backend_repo_url }
output "cluster_name"     { value = module.ecs.cluster_name }
