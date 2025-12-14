#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.${domain}
manage_etc_hosts: true
package_upgrade: true

users:
  - default
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - "${ssh_pub}"

ssh_pwauth: true

runcmd:
  - [ sh, -c, 'mkdir -p /home/ubuntu/.ssh || true' ]
  - [ sh, -c, 'chown -R ubuntu:ubuntu /home/ubuntu/.ssh || true' ]
  - [ sh, -c, 'chmod 700 /home/ubuntu/.ssh || true' ]
  - [ sh, -c, 'chmod 600 /home/ubuntu/.ssh/authorized_keys || true' ]
  # Defensive: ensure home dir owned by ubuntu
  - [ sh, -c, 'chown -R ubuntu:ubuntu /home/ubuntu || true' ]