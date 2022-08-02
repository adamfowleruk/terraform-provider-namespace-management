terraform {
  required_providers {
    vsphere = {
      version = ">= 2.1.1"
      source = "hashicorp/vsphere"
    }
  }
}


data "vsphere_datacenter" "datacenter" {
  name = var.vsphere_datacenter
}

data "vsphere_host" "host" {
  count         = length(var.vds_esxi_hosts)
  name          = var.vds_esxi_hosts[count.index]
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

resource "vsphere_distributed_virtual_switch" "switch" {
  name            = var.vds_switch_name
  datacenter_id   = data.vsphere_datacenter.datacenter.id
  
  max_mtu         = var.vds_switch_max_mtu
  allow_mac_changes = var.vds_switch_security_mac_changes

  uplinks         = [
    var.vds_switch_active_uplinks,
    var.vds_switch_standby_uplinks
  ]
  active_uplinks  = [var.vds_switch_active_uplinks]
  standby_uplinks = [var.vds_switch_standby_uplinks]

  # for all hosts

  dynamic "host" {
    for_each = data.vsphere_host.host

    content {
      host_system_id = host.id
      devices = ["${var.vds_network_interfaces}"]
    }
  }

  # host {
  #   host_system_id = data.vsphere_host.host.0.id
  #   devices        = ["${var.management_network_interfaces}"]
  # }

  # host {
  #   host_system_id = data.vsphere_host.host.1.id
  #   devices        = ["${var.management_network_interfaces}"]
  # }

  # host {
  #   host_system_id = data.vsphere_host.host.2.id
  #   devices        = ["${var.management_network_interfaces}"]
  # }
}

resource "vsphere_distributed_port_group" "portgroup" {
  name                            = var.vds_portgroup_name
  distributed_virtual_switch_uuid = vsphere_distributed_virtual_switch.switch.id

  vlan_id = var.vds_portgroup_vlan
}


# Returns output variables
output "switch" {
  value = vsphere_distributed_virtual_switch.switch.id
}

output "network" {
  value = vsphere_distributed_port_group.portgroup.id
}