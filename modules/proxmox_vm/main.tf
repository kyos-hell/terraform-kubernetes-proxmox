resource "proxmox_virtual_environment_vm" "this" {
  name      = var.fqdn
  node_name = var.node_name
  on_boot   = true

  agent { enabled = true }
  tags = var.tags

  cpu {
    type    = "x86-64-v2-AES"
    cores   = var.cpu
    sockets = 1
  }

  memory {
    dedicated = var.memory
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  disk {
    interface    = "scsi0"
    iothread     = true
    datastore_id = var.system_disk.storage
    discard      = "ignore"
    size         = var.system_disk.size
  }

  dynamic "disk" {
    for_each = var.additionnal_disks
    content {
      interface    = "scsi${1 + disk.key}"
      iothread     = true
      datastore_id = disk.value.storage
      discard      = "ignore"
      file_format  = "raw"
      size         = disk.value.size
    }
  }

  clone {
    vm_id = var.template_vm
  }

  initialization {
    datastore_id      = "local"
    interface         = "ide2"
    user_data_file_id = var.cloud_user_file_id
    meta_data_file_id = var.cloud_meta_file_id

    ip_config {
      ipv4 {
        address = "${var.ip}/${var.network_prefix}"
        gateway = var.gateway_ipv4
      }
    }
  }

  lifecycle {
    ignore_changes = [
      network_device,
      started,
      disk[0].iothread,
      disk[0].discard,
    ]
  }

  boot_order    = ["scsi0"]
  scsi_hardware = "virtio-scsi-single"
}
