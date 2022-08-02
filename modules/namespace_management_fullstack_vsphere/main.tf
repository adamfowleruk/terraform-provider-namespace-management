terraform {
  required_providers {
    // Force local binary use, rather than public binary
    namespace-management = {
      version = ">= 0.1"
      source  = "vmware.com/vcenter/namespace-management"
    }
    vsphere = {
      version = ">= 2.1.1"
      source = "hashicorp/vsphere"
    }
    # Fix for random 401s when initialising Avi
    avi = {
      version = "21.1.2-p1.0"
      source  = "vmware/avi"
    }
  }
}

provider "namespace-management" {
  vsphere_hostname = var.vsphere_hostname
  vsphere_username = var.vsphere_username
  vsphere_password = var.vsphere_password
  vsphere_insecure = var.vsphere_insecure
}

provider "vsphere" {
  vsphere_server = var.vsphere_hostname
  user           = var.vsphere_username
  password       = var.vsphere_password
  api_timeout    = var.vsphere_api_timeout
  # debug_client   = true

  # If you have a self-signed cert
  allow_unverified_ssl = var.vsphere_insecure
}

# module "dc" {
#   source = "./01_vcenter_create"

#   datacenter = var.datacenter_name
#   esxi_hosts = var.esxi_hosts
# }

# module "cluster" {
#   source = "./02_vcenter_join"

#   # Set these values if you are not using the defaults in vcsim
#   # datacenter_name = "lab01.my.cloud"
#   # cluster_name = "Cluster01"
#   # esxi_hosts = [
#   #   "vesxi01.lab01.my.cloud",
#   #   "vesxi02.lab01.my.cloud",
#   #   "vesxi03.lab01.my.cloud",
#   # ]
#   datacenter_name = var.datacenter_name
#   cluster_name = var.cluster_name
#   esxi_hosts = var.esxi_hosts

#   # depends_on = [module.dc]
# }

module "vsphere-networking-management-network" {
  source = "../vsphere_networking_vds"

  // Management vSwitch
  // Note 1: May already exist (probably!)
  // Note 2: May be the same as the workload switch (for small / demo environments)
  vsphere_datacenter = var.vsphere_datacenter
  vds_esxi_hosts = var.esxi_hosts
  vds_switch_name = var.management_switch_name
  vds_switch_allow_mac_changes = var.management_switch_allow_mac_changes
  vds_switch_max_mtu = var.management_switch_max_mtu
  vds_switch_interfaces = var.management_switch_interfaces
  vds_switch_active_uplinks = var.management_switch_active_uplinks
  vds_switch_standby_uplinks = var.management_switch_standby_uplinks
  vds_portgroup_name = var.management_network_name
  vds_portgroup_vlan = var.management_network_vlan
}

module "vsphere-networking-data-network" {
  source = "../vsphere_networking_vds"
  depends_on = [
    module.vsphere-networking-management-network
  ]

  // Avi's Switch and network (Data network aka VIP network)
  // Note 1: Switch may already exist
  // Note 2: May be the same as the management switch (for small / demo environments)
  // Note 2: May be the same as the workload switch (for most prod environments)
  vsphere_datacenter = var.vsphere_datacenter
  vds_esxi_hosts = var.esxi_hosts
  vds_switch_name = var.data_switch_name
  vds_switch_allow_mac_changes = var.data_switch_allow_mac_changes
  vds_switch_interfaces = var.data_switch_interfaces
  vds_switch_active_uplinks = var.data_switch_active_uplinks
  vds_switch_standby_uplinks = var.data_switch_standby_uplinks
  vds_switch_max_mtu = var.data_switch_max_mtu
  vds_portgroup_name = var.data_network_name
  vds_portgroup_vlan = var.data_network_vlan
}

module "vsphere-networking-workload-network" {
  source = "../vsphere_networking_vds"
  depends_on = [
    module.vsphere-networking-management-network,
    module.vsphere-networking-data-network
  ]

  // Tanzu first workload network
  // Note 1: May already exist
  // Note 2: May be the same as the data switch (for most prod environments)
  vsphere_datacenter = var.vsphere_datacenter
  vds_esxi_hosts = var.esxi_hosts
  vds_switch_name = var.workload_switch_name
  vds_switch_allow_mac_changes = var.workload_switch_allow_mac_changes
  vds_switch_interfaces = var.workload_switch_interfaces
  vds_switch_active_uplinks = var.workload_switch_active_uplinks
  vds_switch_standby_uplinks = var.workload_switch_standby_uplinks
  vds_switch_max_mtu = var.workload_switch_max_mtu
  vds_portgroup_name = var.workload_network_name
  vds_portgroup_vlan = var.workload_network_vlan
}

module "avi-controller" {
  source = "../avi_controller_vsphere"
  depends_on = [
    module.vsphere-networking-management-network,
    module.vsphere-networking-data-network,
    module.vsphere-networking-workload-network
  ]

  # vSphere existing infrastructure
  vm_datacenter = var.vsphere_datacenter
  vm_datastore = var.vsphere_vm_datastore
  vm_folder = var.vsphere_vm_folder

  # Manually created for Avi before install:-
  content_library = var.avi_content_library
  vm_template = var.avi_vm_template

  # The rest we create for the user
  vm_resource_pool = var.avi_vm_resource_pool
  vm_network = var.management_network_name
  vm_name = var.avi_vm_name // patterned for -1, -2 etc.

  // Specified here because we've not created Avi yet
  avi_username = var.avi_username
  avi_password = var.avi_password

  // template customisation
  avi_management_hostname = var.avi_management_hostname
  // TODO support multiple controller instances
  avi_management_ip_address = var.avi_management_address_ipv4
  // 27 == "255.255.255.224"
  avi_management_subnet_mask_int = var.management_subnet_mask_int
  avi_management_default_gateway = var.management_default_gateway

  // output avi_cluster_output
}


provider "avi" {
  avi_username   = var.avi_username
  avi_password   = var.avi_password
  avi_tenant     = var.avi_tenant
  avi_controller = var.avi_management_address_ipv4

  # Required for Terraform provider not to puke
  # Without this it complains about 'common_criteria' being there (even though false by default) as the terraform provider defaults to v18.8
  avi_version = var.avi_version
}

module "avi-config" {
  source = "../avi_configure_cloud_vsphere"
  depends_on = [module.avi-controller]

  # vSphere existing infrastructure
  vm_datacenter = var.vsphere_datacenter
  vm_cluster = var.vsphere_cluster
  esxi_vm_name = var.esxi_vm_name

  # The rest we create for the user
  avi_management_network_name = var.management_network_name

  // Specified here because we've not created Avi yet
  avi_username = var.avi_username
  avi_password = var.avi_password

  // Modify the cloud from Default
  avi_cloud_name = var.avi_cloud_name

  // template customisation
  avi_management_dns_server = var.management_dns_server
  # TODO why are there two of these? :-
  avi_management_dns_suffix = var.management_domain
  avi_management_domain = var.management_domain
  avi_management_hostname = var.avi_management_hostname
  // TODO support multiple controller instances
  avi_management_ip_address = var.avi_management_address_ipv4
  avi_management_ip_address_start = var.management_start_ipv4
  avi_management_ip_address_end = var.management_end_ipv4
  // 27 == "255.255.255.224"
  avi_management_ip_network = var.management_network_ipv4
  avi_management_subnet_mask_int = var.management_subnet_mask_int
  avi_management_default_gateway = var.management_default_gateway

  avi_ntp_server = var.management_ntp_server1

  avi_deployment_name = var.deployment_name

  avi_data_network_name = var.data_network_name
  avi_data_network_start_ipv4 = var.data_network_start_ipv4
  avi_data_network_end_ipv4 = var.data_network_end_ipv4
  // Note leaving .40-.61 for Tanzu Workload Network IPs...
  // This is because h2o only gives us one workload network!!!
  // (pfsense vm to the rescue???)
  avi_data_network_network_ipv4 = var.data_network_ipv4
  avi_data_network_subnet_mask_int = var.data_network_subnet_mask_int
  avi_data_network_default_gateway = var.data_network_default_gateway

  vcenter_username = var.vsphere_username
  vcenter_password = var.vsphere_password
  # WARNING THE BELOW IS HOSTNAME/IP ONLY, NO HTTPS OR REQUEST PATH
  vcenter_url = var.vsphere_hostname

  // Make this different from the admin password...
  avi_backup_passphrase = var.avi_backup_passphrase
}

module "tanzu" {
  source = "../tanzu_enable_supervisor"
  depends_on = [module.avi-config]

  // The following 6 items must already exist, along with the 2 vDS networks
  datacenter_name = var.vsphere_datacenter
  cluster_name = var.vsphere_cluster
  image_storage_policy_name = var.tanzu_image_storage_policy_name
  master_storage_policy_name = var.tanzu_supervisor_storage_policy_name
  ephemeral_storage_policy_name = var.tanzu_ephemeral_storage_policy_name
  default_kubernetes_service_content_library_name = var.tanzu_default_kubernetes_service_content_library_name

  master_dns_servers = var.management_dns_server
  master_dns_search_domain = var.management_domain
  master_ntp_servers = var.management_ntp_server1
  master_dns_names = var.tanzu_supervisor_dns_names
  master_network_provider = "VSPHERE_NETWORK"
  master_network_name = var.management_network_name

  master_network_static_gateway_ipv4 = var.management_default_gateway
  master_network_static_starting_address_ipv4 = var.tanzu_supervisor_start_ipv4
  master_network_static_address_count = var.tanzu_supervisor_address_count
  master_network_static_subnet_mask = var.management_subnet_mask_long

  data_network_static_starting_address_ipv4 = var.data_network_start_ipv4
  data_network_static_address_count = var.data_network_address_count

  worker_dns_servers = var.workload_dns_server
  workload_ntp_servers = var.workload_ntp_server1
  primary_workload_network_name = var.workload_network_name
  primary_workload_network_provider = "VSPHERE_NETWORK"
  primary_workload_network_static_gateway_ipv4 = var.workload_default_gateway
  primary_workload_network_static_starting_address_ipv4 = var.workload_start_ipv4
  primary_workload_network_static_address_count = var.workload_address_count
  primary_workload_network_static_subnet_mask = var.workload_subnet_mask_long
  primary_workload_network_vsphere_portgroup_name = var.workload_network_name
  load_balancer_provider = "AVI"
  load_balancer_avi_host = var.avi_management_address_ipv4
  load_balancer_avi_port = var.avi_management_port
  load_balancer_avi_username = var.avi_username
  load_balancer_avi_password = var.avi_password

  # load_balancer_avi_ca_chain = "${module.avi-config.cert.certificate}${module.avi-config.rootcert.certificate}"
  # Not in quotes to avoid potential poor formatting issue
  load_balancer_avi_ca_chain = module.avi-config.cert.certificate
}

# OUTPUT FROM INITIAL AVI CONTROLLER INSTALLATION
output "avi_initial_config" {
  value = module.avi-controller.initial_configuration
  # sensitive = true
}
output "avi_admin_user" {
  value = module.avi-controller.admin_user
  sensitive = true
}

// OUTPUT FROM AVI CONFIGURATION
output "avi_final_config" {
  value = module.avi-config.system_configuration
  sensitive = true
}
output "avi_cloud" {
  value = module.avi-config.cloud
  sensitive = true
}
output "avi_data_network" {
  value = module.avi-config.data_network
}
output "avi_management_network" {
  value = module.avi-config.management_network
}

output "vds_management_switch_id" {
  value = module.vsphere-networking-management-network.switch
}
output "vds_management_network_id" {
  value = module.vsphere-networking-management-network.network
}
output "vds_data_switch_id" {
  value = module.vsphere-networking-data-network.switch
}
output "vds_data_network_id" {
  value = module.vsphere-networking-data-network.network
}
output "vds_workload_switch_id" {
  value = module.vsphere-networking-workload-network.switch
}
output "vds_workload_network_id" {
  value = module.vsphere-networking-workload-network.network
}
# output "cachain" {
#   value = module.avi-config.cachain
# }
