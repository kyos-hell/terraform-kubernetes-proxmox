locals {
  vms_map = { for vm in var.vms : vm.name => vm }
}

module "vm" {
  source   = "./modules/proxmox_vm"
  for_each = local.vms_map

  name               = each.value.name
  fqdn               = "${each.value.name}.${var.domain}"
  ip                 = each.value.ip
  cpu                = each.value.cpu
  memory             = each.value.memory
  role               = each.value.role
  template_vm        = data.proxmox_virtual_environment_vms.template.vms[0].vm_id
  node_name          = var.target_node
  network_bridge     = var.network_bridge
  system_disk        = var.system_disk
  cloud_user_file_id = proxmox_virtual_environment_file.cloud_user_config[each.key].id
  cloud_meta_file_id = proxmox_virtual_environment_file.cloud_meta_config[each.key].id

  network_prefix = var.network_prefix
  gateway_ipv4   = var.gateway_ipv4
  tags           = var.vm_tags
}
