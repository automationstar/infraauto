# Azure Active Directory Server

resource "azuread_application" "server" {
  display_name            = "k8s_server_${var.prefix}"
  reply_urls              = ["http://k8s_server"]
  type                    = "webapp/api"
  group_membership_claims = "All"

  required_resource_access {
    # Windows Azure Active Directory API
    resource_app_id = ""

    resource_access {
      # DELEGATED PERMISSIONS: "Sign in and read user profile":
      id   = ""
      type = "Scope"
    }
  }

  required_resource_access {
    # MicrosoftGraph API
    resource_app_id = ""

    # APPLICATION PERMISSIONS: "Read directory data":
    resource_access {
      id   = ""
      type = "Role"
    }

    # DELEGATED PERMISSIONS: "Sign in and read user profile":
    resource_access {
      id   = ""
      type = "Scope"
    }

    # DELEGATED PERMISSIONS: "Read directory data":
    resource_access {
      id   = ""
      type = "Scope"
    }
  }
}

resource "azuread_service_principal" "server" {
  application_id = azuread_application.server.application_id
}

resource "azuread_service_principal_password" "server" {
  service_principal_id = azuread_service_principal.server.id
  value                = random_string.application_server_password.result
  end_date             = timeadd(timestamp(), "87600h") # 10 years

  # The end date will change at each run (terraform apply), causing a new password to
  # be set. So we ignore changes on this field in the resource lifecyle to avoid this
  # behaviour.
  # If the desired behaviour is to change the end date, then the resource must be
  # manually tainted.
  lifecycle {
    ignore_changes = [end_date]
  }
}

# Passwords

resource "random_string" "application_server_password" {
  length  = 16
  special = true

  keepers = {
    service_principal = azuread_service_principal.server.id
  }
}

resource "random_string" "velero_password" {
  length  = 5
  special = false
  upper   = false
}

resource "random_string" "velero_storage_account" {
  length  = 5
  special = false
  upper   = false
}

resource "random_string" "vault_password" {
  length  = 5
  special = false
  upper   = false
}

resource "random_string" "vault_storage_account" {
  length  = 5
  special = false
  upper   = false
}

resource "random_string" "terraform_password" {
  length  = 5
  special = false
  upper   = false
}

# Azure AD Client

resource "azuread_application" "client" {
  name       = "k8s_client_${var.prefix}"
  reply_urls = ["http://k8s_client"]
  type       = "native"

  required_resource_access {
    # Windows Azure Active Directory API
    resource_app_id = ""

    resource_access {
      # DELEGATED PERMISSIONS: "Sign in and read user profile":
      id   = "311a71cc-e848-46a1-bdf8-97ff7156d8e6"
      type = "Scope"
    }
  }

  required_resource_access {
    # AKS ad application server
    resource_app_id = azuread_application.server.application_id

    resource_access {
      # Server app Oauth2 permissions id
      id   = lookup(azuread_application.server.oauth2_permissions[0], "id")
      type = "Scope"
    }
  }
}

resource "azuread_service_principal" "client" {
  application_id = azuread_application.client.application_id
}

resource "azuread_service_principal_password" "client" {
  service_principal_id = azuread_service_principal.client.id
  value                = random_string.application_client_password.result
  end_date             = timeadd(timestamp(), "87600h")

  lifecycle {
    ignore_changes = [end_date]
  }
}

resource "random_string" "application_client_password" {
  length  = 16
  special = true

  keepers = {
    service_principal = azuread_service_principal.client.id
  }
}

# Velero

resource "azuread_application" "velero" {
  name                    = "k8s_velero_${var.prefix}"
  reply_urls              = ["http://k8s_velero"]
  type                    = "webapp/api"
  group_membership_claims = "All"

  required_resource_access {
    # Windows Azure Active Directory API
    resource_app_id = ""

    resource_access {
      # DELEGATED PERMISSIONS: "Sign in and read user profile":
      id   = ""
      type = "Scope"
    }
  }

  required_resource_access {
    # MicrosoftGraph API
    resource_app_id = ""

    # APPLICATION PERMISSIONS: "Read directory data":
    resource_access {
      id   = ""
      type = "Role"
    }

    # DELEGATED PERMISSIONS: "Sign in and read user profile":
    resource_access {
      id   = ""
      type = "Scope"
    }

    # DELEGATED PERMISSIONS: "Read directory data":
    resource_access {
      id   = ""
      type = "Scope"
    }
  }
}

resource "azuread_service_principal" "velero" {
  application_id = azuread_application.velero.application_id
}

resource "azuread_service_principal_password" "velero" {
  service_principal_id = azuread_service_principal.velero.id
  value                = random_string.velero_password.result
  end_date             = timeadd(timestamp(), "87600h") # 10 years

  # The end date will change at each run (terraform apply), causing a new password to
  # be set. So we ignore changes on this field in the resource lifecyle to avoid this
  # behaviour.
  # If the desired behaviour is to change the end date, then the resource must be
  # manually tainted.
  lifecycle {
    ignore_changes = [end_date]
  }
}

# Vault

resource "azuread_application" "vault" {
  name     = "k8s_vault_${var.prefix}"
  homepage = "https://vault.govcloud.ca"
  # reply_urls              = ["https://vault.govcloud.ca/ui/vault/auth/oidc/oidc/callback", "http://localhost:8250/oidc/callback"]
  type                    = "webapp/api"
  group_membership_claims = "All"

  required_resource_access {
    # Windows Azure Active Directory API
    resource_app_id = ""

    resource_access {
      # DELEGATED PERMISSIONS: "Read all groups":
      id   = ""
      type = "Scope"
    }
  }
}

resource "azurerm_user_assigned_identity" "vault" {
  resource_group_name = azurerm_resource_group.rg_aks.name
  location            = azurerm_resource_group.rg_aks.location

  name = "vault"
}

resource "azuread_service_principal" "vault" {
  application_id = azuread_application.vault.application_id
}

resource "azuread_service_principal_password" "vault" {
  service_principal_id = azuread_service_principal.vault.id
  value                = random_string.vault_password.result
  end_date             = timeadd(timestamp(), "87600h") # 10 years

  # The end date will change at each run (terraform apply), causing a new password to
  # be set. So we ignore changes on this field in the resource lifecyle to avoid this
  # behaviour.
  # If the desired behaviour is to change the end date, then the resource must be
  # manually tainted.
  lifecycle {
    ignore_changes = [end_date]
  }
}

resource "azurerm_role_assignment" "cluster_vault_msi_operator" {
  name                 = ""
  scope                = azurerm_user_assigned_identity.vault.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azuread_service_principal.client.id
}

resource "azurerm_role_assignment" "cluster_velero_sa_contributor" {
  name                 = ""
  scope                = azurerm_storage_account.sa_velero.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azuread_service_principal.velero.id
}

resource "azurerm_role_assignment" "cluster_vnet_network_contributor" {
  name                 = ""
  scope                = azurerm_virtual_network.vnet_aks.id
  role_definition_name = "Network Contributor"
  principal_id         = azuread_service_principal.client.id
}

# # Terraform Service Principal

# resource "azuread_service_principal" "terraform" {
#   application_id = var.client_id
# }

# resource "azuread_service_principal_password" "terraform" {
#   service_principal_id = azuread_service_principal.terraform.id
#   value                = random_string.terraform_password.result
#   end_date             = timeadd(timestamp(), "87600h") # 10 years

#   # The end date will change at each run (terraform apply), causing a new password to
#   # be set. So we ignore changes on this field in the resource lifecyle to avoid this
#   # behaviour.
#   # If the desired behaviour is to change the end date, then the resource must be
#   # manually tainted.
#   lifecycle {
#     ignore_changes = [end_date]
#   }
# }
