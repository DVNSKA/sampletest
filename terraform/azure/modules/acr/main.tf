variable "project"             { type = string }
variable "environment"         { type = string }
variable "resource_group_name" { type = string }
variable "location"            { type = string }

resource "azurerm_container_registry" "main" {
  name                = "${replace(var.project, "-", "")}${var.environment}acr"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.environment == "prod" ? "Standard" : "Basic"
  admin_enabled       = true
  tags = { Environment = var.environment, Project = var.project }
}

output "acr_login_server"   { value = azurerm_container_registry.main.login_server }
output "acr_admin_username" { value = azurerm_container_registry.main.admin_username }
output "acr_admin_password" {
  value     = azurerm_container_registry.main.admin_password
  sensitive = true
}
output "acr_name" { value = azurerm_container_registry.main.name }
