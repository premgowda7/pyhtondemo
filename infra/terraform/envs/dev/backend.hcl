# Created once by scripts/bootstrap-azure.sh. Entra ID auth - no access keys.
resource_group_name  = "rg-orders-tfstate"
storage_account_name = "REPLACE_TFSTATE_STORAGE_ACCOUNT"
container_name       = "tfstate"
key                  = "orders-platform/dev.tfstate"
use_azuread_auth     = true
