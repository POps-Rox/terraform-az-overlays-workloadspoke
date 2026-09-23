# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

/*
SUMMARY: Module to deploy a subnet in the Workload Spoke Network based on the Azure Mission Landing Zone conceptual architecture
DESCRIPTION: The following components will be options in this deployment
              * Workload Spoke Subnets      
AUTHOR/S: jrspinella
*/

#--------------------------------------------------------------------------------------------------------
# Subnets Creation with, private link endpoint/service network policies, service endpoints and Delegation.
#--------------------------------------------------------------------------------------------------------

resource "azurerm_subnet" "default_snet" {
  for_each             = var.spoke_subnets
  name                 = var.custom_spoke_subnet_name == null || var.custom_spoke_subnet_name == "" ? data.popsrox_resource_name.snet[each.key].result : "${var.custom_spoke_subnet_name}_${each.key}"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.spoke_vnet.name
  address_prefixes     = each.value.address_prefixes

  dynamic "service_endpoint" {
    for_each = each.value.service_endpoints

    content {
      service = service_endpoint.value
    }
  }

  # Applicable to the subnets which used for Private link endpoints or services
  # azurerm 4.x replaced `private_endpoint_network_policies_enabled` (bool) with
  # `private_endpoint_network_policies` (string enum: "Enabled" / "Disabled" /
  # "NetworkSecurityGroupEnabled" / "RouteTableEnabled"). The module input variable
  # remains `bool` for backward compatibility — converted here.
  private_endpoint_network_policies = lookup(each.value, "private_endpoint_network_policies_enabled", null) == null ? null : (
    lookup(each.value, "private_endpoint_network_policies_enabled") ? "Enabled" : "Disabled"
  )
  private_link_service_network_policies_enabled = lookup(each.value, "private_link_service_network_policies_enabled", null)

  dynamic "delegation" {
    for_each = each.value["delegation"] == null ? [] : [1]
    content {
      name = each.value.delegation.name == null ? null : each.value.delegation.name
      service_delegation {
        name    = each.value.delegation.service_delegation.name == null ? null : each.value.delegation.service_delegation.name
        actions = each.value.delegation.service_delegation.actions == null ? null : each.value.delegation.service_delegation.actions
      }
    }
  }
}
