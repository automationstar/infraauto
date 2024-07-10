locals {
  # vm_data_from_csv          = fileexists("virtual_machines.csv") ? tolist(concat(tolist(csvdecode(file("virtual_machines.csv"))),tolist(var.virtual_machines))) : var.virtual_machines
  # vms_from_csv = tolist(flatten([
  #   for idx, vm in local.vm_data_from_csv : tolist([ 
  #   {
  #     name                          = vm.name
  #     subnet_name                   = vm.subnet_name
  #     ud_resource_group             = vm.ud_resource_group
  #     vm_size                       = vm.vm_size != "auto" ? vm.vm_size : "Standard_DS1_v2"
  #     os_type                       = vm.os_type != "auto" ? vm.os_type : "linux"
  #     os_disk_name                  = vm.os_disk_name
  #     os_disk_caching               = vm.os_disk_caching != "auto" ? vm.os_disk_caching : "ReadWrite"
  #     os_disk_storage_account_type  = "Standard_LRS"
  #     private_ip_address_allocation = "Static"
  #     ip_index                      = idx
  #     managed_disks                 = null
  #   }
  # ])]))

  # vm_list = length(local.vms_from_csv) > 0 ? merge(local.vms_from_csv, var.virtual_machines) : var.virtual_machines
  vm_list = var.virtual_machines

  nics = {
    for vm in local.vm_list : vm.name => (vm.ip_index != null) ?
    merge(vm, { private_ip_address : cidrhost(azurerm_subnet.subnets[vm.subnet_name].address_prefixes[0], 3 + vm.ip_index) }) :
    vm
  }
}

# Create network interfaces
resource "azurerm_network_interface" "nics" {
  for_each = local.nics

  name                = "nic-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.key}"
  location            = var.location
  resource_group_name = azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name

  ip_configuration {
    name                          = each.value.name
    subnet_id                     = azurerm_subnet.subnets[each.value.subnet_name].id
    private_ip_address_allocation = each.value.private_ip_address_allocation
    private_ip_address            = each.value.private_ip_address
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

# Connect the nics to the security group
resource "azurerm_network_interface_security_group_association" "nics_nsg_association" {
  for_each = { for vm in local.vm_list : vm.name => vm }

  network_interface_id      = azurerm_network_interface.nics[each.key].id
  network_security_group_id = azurerm_network_security_group.network_security_group[0].id
}

# # Add SSH nsg rule if linux vm is requested
# resource "azurerm_network_security_rule" "ssh_nsg_rule" {
#   count = length([for vm in var.virtual_machines : vm if vm.os_type == "linux"]) > 0 ? 1 : 0

#   resource_group_name         = azurerm_resource_group.network_rg[0].name
#   network_security_group_name = azurerm_network_security_group.network_security_group[0].name

#   name                       = "vm_ssh"
#   priority                   = 3999
#   direction                  = "Inbound"
#   access                     = "Allow"
#   protocol                   = "Tcp"
#   source_port_range          = "*"
#   destination_port_range     = "22"
#   source_address_prefixes    = ["10.93.15.33","10.94.6.52","10.123.99.93","10.93.8.46","10.18.46.255","10.18.18.17","10.228.227.18","10.221.18.181"]
#   destination_address_prefixes = [var.vnet_cidr[0]]
# }

# Generate random text for a unique storage account name
resource "random_id" "random_id" {
  count = length([for vm in var.virtual_machines : vm if vm.os_type == "linux"]) > 0 ? 1 : 0
  keepers = {
    # Generate a new ID only when a new resource group is defined
    resource_group = azurerm_resource_group.network_rg[0].name
  }

  byte_length = 8
}

# # Create storage account for boot diagnostics
# resource "azurerm_storage_account" "my_storage_account" {
#   name                     = "diag${random_id.random_id.hex}"
#   location                 = azurerm_resource_group.rg.location
#   resource_group_name      = azurerm_resource_group.rg.name
#   account_tier             = "Standard"
#   account_replication_type = "LRS"
# }

# Create (and display) an SSH key
resource "tls_private_key" "ssh_key" {
  count     = length([for vm in local.vm_list : vm if vm.os_type == "linux"]) > 0 ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create linux virtual machine
resource "azurerm_linux_virtual_machine" "vms" {
  for_each = { for vm in local.vm_list : vm.name => vm if vm.os_type == "linux" }

  name                       = "vm-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.key}"
  location                   = var.location
  resource_group_name        = azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name
  network_interface_ids      = [azurerm_network_interface.nics[each.key].id]
  size                       = each.value.vm_size
  encryption_at_host_enabled = each.value.encryption_at_host


  os_disk {
    name                   = each.value.os_disk_name
    caching                = each.value.os_disk_caching
    storage_account_type   = each.value.os_disk_storage_account_type
    disk_encryption_set_id = azurerm_disk_encryption_set.vm_disk_encryption_set[0].id
  }

  source_image_reference {
    publisher = "RedHat"
    offer     = "RHEL"
    sku       = "8.1"
    version   = "latest"
  }

  computer_name                   = each.key
  admin_username                  = "azureuser"
  disable_password_authentication = true

  admin_ssh_key {
    username   = "azureuser"
    public_key = tls_private_key.ssh_key[0].public_key_openssh
  }

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.base_kv_uai[0].id]
  }

  #   boot_diagnostics {
  #     storage_account_uri = azurerm_storage_account.my_storage_account.primary_blob_endpoint
  #   }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }

}

# resource "azurerm_network_security_rule" "winrm" {
#   count = length([for vm in var.virtual_machines : vm if vm.os_type == "windows"]) > 0 ? 1 : 0

#   resource_group_name         = azurerm_resource_group.network_rg[0].name
#   network_security_group_name = azurerm_network_security_group.network_security_group[0].name

#   name = "Allow-winrm-rule"
#   priority                   = 3998
#   direction                  = "Inbound"
#   access                     = "Allow"
#   protocol                   = "Tcp"
#   source_port_range          = "*"
#   destination_port_range     = "5986"
#   source_address_prefixes      = ["10.93.15.33","10.94.6.52","10.123.99.93","10.93.8.46","10.18.46.255","10.18.18.17","10.228.227.18","10.221.18.181"]
#   destination_address_prefixes = [var.vnet_cidr[0]]
# }

resource "random_password" "win_default_admin_pass" {
  count = length([for vm in local.vm_list : vm if vm.os_type == "windows"]) > 0 ? 1 : 0

  length           = 120
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# create windows virtual machine
resource "azurerm_windows_virtual_machine" "vms" {
  for_each = { for vm in local.vm_list : vm.name => vm if vm.os_type == "windows" }

  name                       = "vm-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-${each.key}"
  resource_group_name        = azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name
  location                   = var.location
  network_interface_ids      = [azurerm_network_interface.nics[each.key].id]
  size                       = each.value.vm_size
  encryption_at_host_enabled = each.value.encryption_at_host

  computer_name  = each.key
  admin_username = "azureuser"
  admin_password = random_password.win_default_admin_pass[0].result


  os_disk {
    name                   = each.value.os_disk_name
    caching                = each.value.os_disk_caching
    storage_account_type   = each.value.os_disk_storage_account_type
    disk_encryption_set_id = azurerm_disk_encryption_set.vm_disk_encryption_set[0].id
  }

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.base_kv_uai[0].id]
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-datacenter"
    version   = "latest"
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }

}

locals {
  vm_managed_disks = {
    for disk in flatten([
      for vm in local.vm_list : [
        for disk in vm.managed_disks : merge(disk, { vm_name : vm.name, os_type : vm.os_type })
      ] if vm.managed_disks != null
    ]) : "${disk.name}_${disk.vm_name}" => disk
  }

}

resource "azurerm_managed_disk" "managed_disks" {
  for_each = { for md in var.managed_disks : md.name => md }

  name                          = each.value.name
  location                      = var.location
  resource_group_name           = azurerm_resource_group.ud_rgs[each.value.ud_resource_group].name
  storage_account_type          = each.value.storage_account_type
  create_option                 = each.value.create_option
  disk_size_gb                  = each.value.disk_size_gb
  public_network_access_enabled = false
  disk_encryption_set_id        = azurerm_disk_encryption_set.vm_disk_encryption_set[0].id

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }

}

resource "azurerm_virtual_machine_data_disk_attachment" "vm_managed_disk_association" {
  for_each   = local.vm_managed_disks
  depends_on = [azurerm_role_assignment.base_kv_key_access_aes_role_managed_identity]

  managed_disk_id    = azurerm_managed_disk.managed_disks[each.value.name].id
  virtual_machine_id = each.value.os_type == "linux" ? azurerm_linux_virtual_machine.vms[each.value.vm_name].id : azurerm_windows_virtual_machine.vms[each.value.vm_name].id
  lun                = each.value.lun
  caching            = each.value.caching
}

resource "azurerm_disk_encryption_set" "vm_disk_encryption_set" {
  depends_on = [azurerm_private_endpoint.base_kv_pep, local.keys_depend_on]

  count = (length([for vm in local.vm_list : vm]) > 0 && var.is_spoke) ? 1 : 0

  name                = "des-${var.line_of_business}-${var.application_id}-${var.environment}-${local.short_location_name}-vm"
  resource_group_name = azurerm_resource_group.secr_rg[0].name
  location            = var.location
  key_vault_key_id    = local.base_key_id

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.base_kv_uai[0].id]
  }

  tags = local.all_tags
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}