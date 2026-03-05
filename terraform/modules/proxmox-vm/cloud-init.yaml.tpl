#cloud-config
# Injected by Terraform proxmox-vm module

package_update: true
package_upgrade: false

packages:
  - curl
  - ca-certificates
  - apt-transport-https

runcmd:
  # Install Teleport
  - curl https://cdn.teleport.dev/install.sh | bash -s -- teleport-ent 2>/dev/null || curl https://cdn.teleport.dev/install.sh | bash

  # Write Teleport config
  - |
    cat > /etc/teleport.yaml <<'TELEPORT_EOF'
    version: v3
    teleport:
      nodename: ${hostname}
      auth_servers:
        - ${teleport_auth_server}
      join_params:
        token_name: ${teleport_join_token}
        method: token
      ca_pin: ${teleport_ca_pin}

    auth_service:
      enabled: false

    proxy_service:
      enabled: false

    ssh_service:
      enabled: true
      labels:
        role: ${role}
        managed-by: terraform
    TELEPORT_EOF

  # Enable and start Teleport
  - systemctl enable teleport
  - systemctl start teleport

ssh_authorized_keys:
  - ${ssh_public_key}
