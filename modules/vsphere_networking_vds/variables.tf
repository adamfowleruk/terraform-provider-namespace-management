# vSphere Cluster variables:-

variable "vsphere_datacenter" {
  type    = string
  default = "vc01"
}

# variable "vsphere_cluster" {
#   type    = string
#   default = "vc01cl01"
# }




# VDS networking specific variables:-

variable "vds_esxi_hosts" {
  default = [
    "vesxi01.lab01.my.cloud",
    "vesxi02.lab01.my.cloud",
    "vesxi03.lab01.my.cloud",
  ]
}

variable "vds_network_interfaces" {
  default = [
    "vmnic0"
  ]
}

variable "vds_switch_name" {
  type = string
  default = "Management Switch"
}

variable "vds_switch_active_uplinks" {
  default = [
    "uplink1"
  ]
}

variable "vds_switch_standby_uplinks" {
  default = [
  ]
}

variable "vds_switch_max_mtu" {
  type = number
  default = 1500
}

variable "vds_switch_allow_mac_changes" {
  type = bool
  default = false
}



variable "vds_portgroup_name" {
  type = string
  default = "Management Network"
}

variable "vds_portgroup_vlan" {
  type = string
  default = "0"
}
