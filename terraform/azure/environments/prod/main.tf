terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.0" }
  }
  backend "azurerm" {
    resource_group_name  = "devops-assignment"
    storage_account_name = "devopstfstate380652"
    container_name       = "tfstate"
    key                  = "azure/prod/terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
  subscription_id = "ba662c37-fbba-4092-8100-347c6d9f46c6"
}

locals {
  project             = "devops-assignment"
  environment         = "prod"
  location            = "centralindia"
  resource_group_name = "devops-assignment"
}

module "acr" {
  source              = "../../modules/acr"
  project             = local.project
  environment         = local.environment
  resource_group_name = local.resource_group_name
  location            = local.location
}

module "container_apps" {
  source              = "../../modules/container-apps"
  project             = local.project
  environment         = local.environment
  resource_group_name = local.resource_group_name
  location            = local.location

  acr_login_server   = module.acr.acr_login_server
  acr_admin_username = module.acr.acr_admin_username
  acr_admin_password = module.acr.acr_admin_password

  frontend_image = "${module.acr.acr_login_server}/frontend:latest"
  backend_image  = "${module.acr.acr_login_server}/backend:latest"

  # Reuse existing dev environment (free tier limit)
  existing_environment_id = "/subscriptions/ba662c37-fbba-4092-8100-347c6d9f46c6/resourceGroups/devops-assignment/providers/Microsoft.App/managedEnvironments/devops-assign-dev-env"

  # PROD: full resources, always 2 instances minimum
  frontend_min_replicas = 2
  frontend_max_replicas = 10
  backend_min_replicas  = 2
  backend_max_replicas  = 10
  frontend_cpu          = 1.0
  frontend_memory       = "2Gi"
  backend_cpu           = 1.0
  backend_memory        = "2Gi"
}

output "frontend_url"     { value = module.container_apps.frontend_url }
output "backend_url"      { value = module.container_apps.backend_url }
output "acr_login_server" { value = module.acr.acr_login_server }
