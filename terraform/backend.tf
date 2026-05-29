terraform {
  backend "azurerm" {
    resource_group_name  = "contapps"
    storage_account_name = "tfstatestoragemra"
    container_name       = "tfstate"
    key                  = "schoolaccount.tfstate"
  }
}