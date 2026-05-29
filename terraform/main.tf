resource "azurerm_container_app" "app" {
  name                         = "schoolaccount-alpha-app-tf"
  resource_group_name          = "contapps"
  container_app_environment_id = data.azurerm_container_app_environment.env.id
  revision_mode                = "Single"

  registry {
    server               = "ghcr.io"
    username             = var.ghcr_username
    password_secret_name = "ghcr-password"
  }

  secret {
    name  = "ghcr-password"
    value = var.ghcr_token
  }

  template {
    container {
      name   = "schoolaccount-alpha-app"
      image  = "ghcr.io/dfe-digital/schoolaccount-alpha-app:latest"
      cpu    = 0.25
      memory = "0.5Gi"
    }
  }

  ingress {
    external_enabled = true
    target_port      = 8080
    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}


data "azurerm_container_app_environment" "env" {
  name                = "contappmra"
  resource_group_name = "contapps"
}