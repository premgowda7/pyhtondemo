terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }

  # Partial config: values come from backend.hcl (see scripts/bootstrap-azure.sh)
  backend "azurerm" {}
}

provider "azurerm" {
  # subscription_id / tenant_id / client_id come from ARM_* env vars (OIDC in GitHub Actions).
  storage_use_azuread = true # no storage account keys anywhere

  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}
