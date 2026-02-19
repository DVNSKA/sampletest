variable "project"             { type = string }
variable "environment"         { type = string }
variable "resource_group_name" { type = string }
variable "location"            { type = string }
variable "acr_login_server"    { type = string }
variable "acr_admin_username"  { type = string }
variable "acr_admin_password" {
  type      = string
  sensitive = true
}
variable "frontend_image"        { type = string }
variable "backend_image"         { type = string }
variable "frontend_min_replicas" { type = number }
variable "frontend_max_replicas" { type = number }
variable "backend_min_replicas"  { type = number }
variable "backend_max_replicas"  { type = number }
variable "frontend_cpu"          { type = number }
variable "frontend_memory"       { type = string }
variable "backend_cpu"           { type = number }
variable "backend_memory"        { type = string }
variable "existing_environment_id" {
  type    = string
  default = ""
}

locals {
  use_existing_env = var.existing_environment_id != ""
  environment_id   = local.use_existing_env ? var.existing_environment_id : azurerm_container_app_environment.main[0].id
  # Shorten name to fit Azure 32 char limit
  # e.g. "devops-assign-staging-be" = 24 chars
  short_project = "devops-assign"
}

resource "azurerm_log_analytics_workspace" "main" {
  count               = local.use_existing_env ? 0 : 1
  name                = "${local.short_project}-${var.environment}-logs"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags = { Environment = var.environment }
}

resource "azurerm_container_app_environment" "main" {
  count                      = local.use_existing_env ? 0 : 1
  name                       = "${local.short_project}-${var.environment}-env"
  resource_group_name        = var.resource_group_name
  location                   = var.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main[0].id
  tags = { Environment = var.environment }
}

resource "azurerm_container_app" "backend" {
  name                         = "${local.short_project}-${var.environment}-be"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = local.environment_id
  revision_mode                = "Single"

  registry {
    server               = var.acr_login_server
    username             = var.acr_admin_username
    password_secret_name = "acr-password"
  }

  secret {
    name  = "acr-password"
    value = var.acr_admin_password
  }

  template {
    min_replicas = var.backend_min_replicas
    max_replicas = var.backend_max_replicas

    container {
      name   = "backend"
      image  = var.backend_image
      cpu    = var.backend_cpu
      memory = var.backend_memory

      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
    }

    http_scale_rule {
      name                = "http-scaling"
      concurrent_requests = "10"
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8000
    transport        = "http"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  tags = { Environment = var.environment }
}

resource "azurerm_container_app" "frontend" {
  name                         = "${local.short_project}-${var.environment}-fe"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = local.environment_id
  revision_mode                = "Single"

  registry {
    server               = var.acr_login_server
    username             = var.acr_admin_username
    password_secret_name = "acr-password"
  }

  secret {
    name  = "acr-password"
    value = var.acr_admin_password
  }

  template {
    min_replicas = var.frontend_min_replicas
    max_replicas = var.frontend_max_replicas

    container {
      name   = "frontend"
      image  = var.frontend_image
      cpu    = var.frontend_cpu
      memory = var.frontend_memory

      env {
        name  = "NODE_ENV"
        value = "production"
      }

      env {
        name  = "NEXT_PUBLIC_API_URL"
        value = "https://${azurerm_container_app.backend.ingress[0].fqdn}"
      }
    }

    http_scale_rule {
      name                = "http-scaling"
      concurrent_requests = "10"
    }
  }

  ingress {
    external_enabled = true
    target_port      = 3000
    transport        = "http"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  tags = { Environment = var.environment }
}

output "frontend_url" { value = "https://${azurerm_container_app.frontend.ingress[0].fqdn}" }
output "backend_url"  { value = "https://${azurerm_container_app.backend.ingress[0].fqdn}" }
