location    = "centralindia"
environment = "dev"

# REQUIRED: object ID of your AKS admins Entra group  (az ad group show -g <name> --query id -o tsv)
aks_admin_group_object_ids = ["00000000-0000-0000-0000-000000000000"]

aks_private_cluster_enabled = true
firewall_enabled            = false

tags = {
  owner       = "platform-team"
  cost_center = "devops"
}
