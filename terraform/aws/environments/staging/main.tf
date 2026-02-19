terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
  backend "s3" {
    bucket  = "devops-assignment-tfstate-380652644852"
    key     = "devops-assignment/aws/staging/terraform.tfstate"
    region  = "ap-south-1"
    encrypt = true
  }
}

provider "aws" {
  region = "ap-south-1"
  default_tags {
    tags = {
      Project     = "devops-assignment"
      Environment = "staging"
      ManagedBy   = "Terraform"
    }
  }
}

locals {
  project     = "devops-assignment"
  environment = "staging"
  region      = "ap-south-1"
}

module "networking" {
  source      = "../../modules/networking"
  project     = local.project
  environment = local.environment
  region      = local.region
  vpc_cidr    = "10.1.0.0/16"
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

  vpc_id             = module.networking.vpc_id
  private_subnet_ids = module.networking.private_subnet_ids
  public_subnet_ids  = module.networking.public_subnet_ids

  ecs_tasks_sg_id = module.alb.ecs_tasks_sg_id
  frontend_tg_arn = module.alb.frontend_tg_arn
  backend_tg_arn  = module.alb.backend_tg_arn

  ecs_task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  ecs_task_role_arn           = module.iam.ecs_task_role_arn

  frontend_image = "${module.ecr.frontend_repo_url}:latest"
  backend_image  = "${module.ecr.backend_repo_url}:latest"
  backend_url    = "http://${module.alb.alb_dns_name}"

  # STAGING: more resources, autoscaling ON (1-3 tasks)
  frontend_cpu       = 512
  frontend_memory    = 1024
  backend_cpu        = 512
  backend_memory     = 1024
  frontend_min_count = 1
  frontend_max_count = 3
  backend_min_count  = 1
  backend_max_count  = 3
}

output "alb_url"          { value = "http://${module.alb.alb_dns_name}" }
output "frontend_ecr_url" { value = module.ecr.frontend_repo_url }
output "backend_ecr_url"  { value = module.ecr.backend_repo_url }
output "cluster_name"     { value = module.ecs.cluster_name }
