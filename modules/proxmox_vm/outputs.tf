output "vm_id" {
  value = proxmox_virtual_environment_vm.this.vm_id
}
output "fqdn" {
  value = proxmox_virtual_environment_vm.this.name
}
output "ip" {
  value = proxmox_virtual_environment_vm.this.ipv4_addresses
}
