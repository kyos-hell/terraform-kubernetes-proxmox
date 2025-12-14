# Shared locals derived from var.vms (keep a single source of truth)
locals {
  vm_ip_map  = { for v in var.vms : v.name => v.ip }
  ansible_ip = lookup(local.vm_ip_map, "ansible-01", "")
}
