# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

resource "azurerm_private_dns_zone_virtual_network_link" "private_dns_zone_vnet_links" {
  count = length(var.private_dns_zone_vnets_ids)

  name = format("%s-link", reverse(split("/", var.private_dns_zone_vnets_ids[count.index]))[0])

  private_dns_zone_id = azurerm_private_dns_zone.private_dns_zone.id
  virtual_network_id  = var.private_dns_zone_vnets_ids[count.index]

  registration_enabled = var.vm_autoregistration_enabled

  tags = local.curtailed_tags

  lifecycle {
    precondition {
      condition     = var.is_not_private_link_service
      error_message = "Private Link Service does not require the deployment of Private DNS Zone VNet Links."
    }
  }
}