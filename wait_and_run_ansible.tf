locals {
  all_ips        = [for v in var.vms : v.ip]
  all_ips_joined = join(" ", local.all_ips)

}

resource "null_resource" "wait_for_vms" {
  depends_on = [
    module.vm,
    null_resource.reboot_ansible,
    null_resource.install_ansible
  ]

  triggers = {
    ips = join(",", local.all_ips)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "${path.root}/scripts/wait_for_ssh.sh 600 ${var.ssh_user} ${var.ssh_key_path} ${local.all_ips_joined}"
  }
}

resource "null_resource" "copy_ansible" {
  depends_on = [
    null_resource.wait_for_vms,
    null_resource.install_ansible,
    null_resource.reboot_ansible
  ]

  triggers = {
    ansible_ip    = local.ansible_ip
    script_md5    = filemd5("${path.root}/scripts/generate_and_copy_ansible.sh")
    inventory_md5 = filemd5("${path.root}/ansible/inventory.ini")
    playbook_md5  = filemd5("${path.root}/ansible/playbook.yml")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "${path.root}/scripts/generate_and_copy_ansible.sh ${path.root} ${var.ssh_user}@${local.ansible_ip} /home/${var.ssh_user}/ansible ${var.ssh_key_path}"
  }
}

# One-liner: generate known_hosts locally and upload it atomically to the control node
resource "null_resource" "populate_known_hosts" {
  depends_on = [
    null_resource.wait_for_vms,
  ]

  triggers = {
    ips = join(",", local.all_ips)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "TMP_KH=$(mktemp) && ssh-keyscan -t rsa,ecdsa,ed25519 ${local.all_ips_joined} 2>/dev/null > $TMP_KH || true && sort -u $TMP_KH -o $TMP_KH || true && ssh -i '${var.ssh_key_path}' -oStrictHostKeyChecking=no ${var.ssh_user}@${local.ansible_ip} 'mkdir -p /home/${var.ssh_user}/.ssh && chmod 700 /home/${var.ssh_user}/.ssh' || true && scp -i '${var.ssh_key_path}' -oStrictHostKeyChecking=no $TMP_KH ${var.ssh_user}@${local.ansible_ip}:/tmp/known_hosts.tf || true && ssh -i '${var.ssh_key_path}' -oStrictHostKeyChecking=no ${var.ssh_user}@${local.ansible_ip} 'mv /tmp/known_hosts.tf /home/${var.ssh_user}/.ssh/known_hosts && chown ${var.ssh_user}:${var.ssh_user} /home/${var.ssh_user}/.ssh/known_hosts && chmod 600 /home/${var.ssh_user}/.ssh/known_hosts' || true && rm -f $TMP_KH || true"
  }
}

# One-liner: ensure public key is present on all VMs in authorized_keys (idempotent)
resource "null_resource" "distribute_pubkey" {
  depends_on = [
    null_resource.wait_for_vms,
    null_resource.populate_known_hosts
  ]

  triggers = {
    # use try(filemd5(...), timestamp()) to avoid fileexists inconsistent-result errors
    pubkey = try(filemd5(var.ssh_key_path), timestamp())
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "PUBKEY_PATH=$(mktemp) && if [ -f '${var.ssh_key_path}.pub' ]; then cp '${var.ssh_key_path}.pub' $PUBKEY_PATH; else ssh-keygen -y -f '${var.ssh_key_path}' > $PUBKEY_PATH; fi && for ip in ${local.all_ips_joined}; do scp -i '${var.ssh_key_path}' -oStrictHostKeyChecking=no $PUBKEY_PATH ${var.ssh_user}@$ip:/tmp/id_ansible.pub || true && ssh -i '${var.ssh_key_path}' -oStrictHostKeyChecking=no ${var.ssh_user}@$ip 'mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && grep -F -x -f /tmp/id_ansible.pub ~/.ssh/authorized_keys >/dev/null 2>&1 || cat /tmp/id_ansible.pub >> ~/.ssh/authorized_keys; rm -f /tmp/id_ansible.pub; chmod 600 ~/.ssh/authorized_keys' || true; done && rm -f $PUBKEY_PATH || true"
  }
}

resource "null_resource" "run_playbook" {
  depends_on = [
    null_resource.copy_ansible,
    null_resource.populate_known_hosts,
    null_resource.distribute_pubkey
  ]

  triggers = {
    run = timestamp()
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "ssh -i '${var.ssh_key_path}' -oStrictHostKeyChecking=no ${var.ssh_user}@${local.ansible_ip} 'cd /home/${var.ssh_user}/ansible && ANSIBLE_HOST_KEY_CHECKING=False /opt/ansible-venv/bin/ansible-playbook -i inventory.ini playbook.yml -v'"
  }
}
