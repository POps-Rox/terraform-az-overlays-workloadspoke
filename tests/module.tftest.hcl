# Functional tests for the workload spoke overlay.
#
# These use mock_provider, so they execute without Azure credentials and are
# safe for pull requests. They exercise module decision logic that validate
# cannot see: naming precedence, conditional resources, tag merging, location
# passthrough, and subnet association branching.

mock_provider "azapi" {}

mock_provider "popsrox" {
  mock_data "popsrox_resource_name" {
    defaults = {
      result = "generated-name"
    }
  }
}

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      object_id       = "00000000-0000-0000-0000-000000000001"
      tenant_id       = "00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000003"
    }
  }

  mock_data "azurerm_resource_group" {
    defaults = {
      name     = "existing-rg"
      location = "eastus"
    }
  }

  mock_data "azurerm_network_watcher" {
    defaults = {
      name = "NetworkWatcher_eastus"
      id   = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/NetworkWatcherRG/providers/Microsoft.Network/networkWatchers/NetworkWatcher_eastus"
    }
  }

  mock_data "azurerm_virtual_network" {
    defaults = {
      name                = "hub-vnet"
      resource_group_name = "hub-rg"
      id                  = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/hub-rg/providers/Microsoft.Network/virtualNetworks/hub-vnet"
    }
  }
}

mock_provider "azurerm" {
  alias = "hub_network"

  mock_data "azurerm_virtual_network" {
    defaults = {
      name                = "hub-vnet"
      resource_group_name = "hub-rg"
      id                  = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/hub-rg/providers/Microsoft.Network/virtualNetworks/hub-vnet"
    }
  }
}

variables {
  location                        = "eastus"
  environment                     = "public"
  deploy_environment              = "dev"
  workload_name                   = "workload"
  org_name                        = "anoa"
  existing_resource_group_name    = "existing-rg"
  hub_virtual_network_name        = "hub-vnet"
  hub_resource_group_name         = "hub-rg"
  hub_firewall_private_ip_address = "10.0.0.4"
  log_analytics_workspace_id      = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/log-rg/providers/Microsoft.OperationalInsights/workspaces/logs"
  log_analytics_customer_id       = "00000000-0000-0000-0000-000000000004"
  disable_telemetry               = true
  virtual_network_address_space   = ["10.10.0.0/16"]
  spoke_subnets = {
    app = {
      name                                       = "app"
      address_prefixes                           = ["10.10.1.0/24"]
      service_endpoints                          = ["Microsoft.Storage"]
      private_endpoint_network_policies_enabled  = true
      private_endpoint_service_endpoints_enabled = false
      nsg_subnet_rules                           = []
    }
    data = {
      name                                       = "data"
      address_prefixes                           = ["10.10.2.0/24"]
      service_endpoints                          = []
      private_endpoint_network_policies_enabled  = false
      private_endpoint_service_endpoints_enabled = false
      nsg_subnet_rules                           = []
    }
  }
  add_tags = {
    costCenter = "cc-1234"
  }
}

# ---------------------------------------------------------------------------
# Naming precedence and empty-string fallthrough
# ---------------------------------------------------------------------------

run "generated_names_are_used_when_custom_names_are_unset" {
  command = plan

  assert {
    condition     = azurerm_virtual_network.spoke_vnet.name == "generated-name"
    error_message = "Expected generated VNet name when custom_spoke_virtual_network_name is unset, got: ${azurerm_virtual_network.spoke_vnet.name}"
  }

  assert {
    condition     = azurerm_subnet.default_snet["app"].name == "generated-name"
    error_message = "Expected generated subnet name when custom_spoke_subnet_name is unset, got: ${azurerm_subnet.default_snet["app"].name}"
  }
}

run "custom_names_override_generated_names" {
  command = plan

  variables {
    custom_spoke_virtual_network_name        = "custom-vnet"
    custom_spoke_subnet_name                 = "custom-snet"
    custom_spoke_network_security_group_name = "custom-nsg"
    custom_spoke_route_table_name            = "custom-rt"
  }

  assert {
    condition     = azurerm_virtual_network.spoke_vnet.name == "custom-vnet"
    error_message = "custom_spoke_virtual_network_name must take precedence, got: ${azurerm_virtual_network.spoke_vnet.name}"
  }

  assert {
    condition     = azurerm_subnet.default_snet["app"].name == "custom-snet_app"
    error_message = "custom_spoke_subnet_name must be used as the subnet prefix, got: ${azurerm_subnet.default_snet["app"].name}"
  }

  assert {
    condition     = azurerm_network_security_group.nsg["app"].name == "custom-nsg_app"
    error_message = "custom_spoke_network_security_group_name must be used as the NSG prefix, got: ${azurerm_network_security_group.nsg["app"].name}"
  }

  assert {
    condition     = azurerm_route_table.routetable.name == "custom-rt"
    error_message = "custom_spoke_route_table_name must take precedence, got: ${azurerm_route_table.routetable.name}"
  }
}

run "empty_custom_names_fall_through_to_generated_names" {
  command = plan

  variables {
    custom_spoke_virtual_network_name        = ""
    custom_spoke_subnet_name                 = ""
    custom_spoke_network_security_group_name = ""
    custom_spoke_route_table_name            = ""
  }

  assert {
    condition     = azurerm_virtual_network.spoke_vnet.name == "generated-name"
    error_message = "Empty VNet custom name must fall through to generated name, got: ${azurerm_virtual_network.spoke_vnet.name}"
  }

  assert {
    condition     = azurerm_subnet.default_snet["app"].name == "generated-name"
    error_message = "Empty subnet custom name must fall through to generated name, got: ${azurerm_subnet.default_snet["app"].name}"
  }

  assert {
    condition     = azurerm_network_security_group.nsg["app"].name == "generated-name"
    error_message = "Empty NSG custom name must fall through to generated name, got: ${azurerm_network_security_group.nsg["app"].name}"
  }
}

# ---------------------------------------------------------------------------
# Conditional resources
# ---------------------------------------------------------------------------

run "disabled_optional_resources_are_not_created" {
  command = plan

  assert {
    condition     = length(azurerm_management_lock.vnet_resource_group_level_lock) == 0
    error_message = "enable_resource_locks defaults to false, so no VNet lock should be planned"
  }

  assert {
    condition     = length(azurerm_network_ddos_protection_plan.ddos) == 0
    error_message = "create_ddos_plan defaults to false, so no DDoS plan should be planned"
  }

  assert {
    condition     = length(azurerm_route.force_internet_tunneling) == 0
    error_message = "enable_forced_tunneling_on_route_table defaults to false, so no forced-tunnel route should be planned"
  }
}

run "enabled_optional_resources_are_created" {
  command = plan

  variables {
    enable_resource_locks                  = true
    create_ddos_plan                       = true
    ddos_plan_name                         = "ddos-plan"
    enable_forced_tunneling_on_route_table = true
  }

  assert {
    condition     = length(azurerm_management_lock.vnet_resource_group_level_lock) == 1
    error_message = "enable_resource_locks = true must create exactly one VNet lock"
  }

  assert {
    condition     = length(azurerm_network_ddos_protection_plan.ddos) == 1
    error_message = "create_ddos_plan = true must create exactly one DDoS plan"
  }

  assert {
    condition     = length(azurerm_route.force_internet_tunneling) == 1
    error_message = "enable_forced_tunneling_on_route_table = true must create exactly one forced-tunnel route"
  }
}

# ---------------------------------------------------------------------------
# Tagging, location, and subnet branching
# ---------------------------------------------------------------------------

run "tags_and_location_are_passed_through" {
  command = plan

  assert {
    condition     = azurerm_virtual_network.spoke_vnet.location == "eastus"
    error_message = "The VNet location must come from the selected resource group location, got: ${azurerm_virtual_network.spoke_vnet.location}"
  }

  assert {
    condition     = lookup(azurerm_virtual_network.spoke_vnet.tags, "costCenter", "") == "cc-1234"
    error_message = "Caller-supplied add_tags must be merged onto the VNet"
  }

  assert {
    condition     = azurerm_virtual_network.spoke_vnet.tags["env"] == "dev"
    error_message = "Default tags must include the deploy environment"
  }
}

run "subnets_drive_nsgs_route_tables_and_flow_logs" {
  command = plan

  assert {
    condition     = length(azurerm_subnet.default_snet) == 2
    error_message = "Each spoke_subnets entry must create one subnet"
  }

  assert {
    condition     = length(azurerm_network_security_group.nsg) == 2
    error_message = "Each spoke_subnets entry must create one NSG"
  }

  assert {
    condition     = length(azurerm_subnet_network_security_group_association.nsgassoc) == 2
    error_message = "Each spoke_subnets entry must create one subnet-to-NSG association"
  }

  assert {
    condition     = length(azurerm_subnet_route_table_association.rtassoc) == 2
    error_message = "Each spoke_subnets entry must create one subnet-to-route-table association"
  }

  assert {
    condition     = length(azurerm_network_watcher_flow_log.nwflog) == 2
    error_message = "Each spoke_subnets entry must create one Network Watcher flow log"
  }

  assert {
    condition     = azurerm_subnet.default_snet["app"].private_endpoint_network_policies == "Enabled"
    error_message = "private_endpoint_network_policies_enabled = true must map to azurerm 5.x value Enabled"
  }

  assert {
    condition     = azurerm_subnet.default_snet["app"].service_endpoint[0].service == "Microsoft.Storage"
    error_message = "Subnet service_endpoints input must populate the azurerm 5.x service_endpoint block"
  }

  assert {
    condition     = azurerm_subnet.default_snet["data"].private_endpoint_network_policies == "Disabled"
    error_message = "private_endpoint_network_policies_enabled = false must map to azurerm 5.x value Disabled"
  }
}
