output "vms" {
  value = { for k, m in module.vm : k => {
    fqdn = m.fqdn
    ip   = m.ip
    id   = m.vm_id
  } }
  description = "Map of VM name => { fqdn, ip, id }"
}
