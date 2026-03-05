# ── GitHub Actions runner (existing LXC — import with terraform import) ──────

module "runner" {
  source = "../../modules/proxmox-lxc"

  vmid        = 110
  hostname    = "starstalk-runner"
  cores       = 2
  memory_mb   = 2048
  disk_gb     = 20
  ip_cidr     = "192.168.0.77/24"
  gateway     = "192.168.0.1"
  proxmox_node = var.proxmox_node
  storage     = "local-lvm"
  bridge      = "vmbr0"

  ssh_public_key = var.ssh_public_key

  teleport_join_token  = teleport_provision_token.lxc_nodes.metadata[0].name
  teleport_auth_server = var.teleport_auth_server
  teleport_ca_pin      = var.teleport_ca_pin
  role                 = "github-runner"
}

# ── k3s control plane VM ─────────────────────────────────────────────────────

module "k3s_control" {
  source = "../../modules/proxmox-vm"

  vmid        = 120
  hostname    = "k3s-control"
  cores       = 2
  memory_mb   = 2048
  disk_gb     = 20
  ip_cidr     = "192.168.0.80/24"
  gateway     = "192.168.0.1"
  proxmox_node = var.proxmox_node
  storage     = "local-lvm"
  bridge      = "vmbr0"

  os_image_id    = proxmox_virtual_environment_download_file.ubuntu_24_04.id
  ssh_public_key = var.ssh_public_key

  teleport_join_token  = teleport_provision_token.vm_nodes.metadata[0].name
  teleport_auth_server = var.teleport_auth_server
  teleport_ca_pin      = var.teleport_ca_pin
  role                 = "k3s-control"
}

# ── k3s worker VMs (scale via var.worker_count) ───────────────────────────────

module "k3s_workers" {
  source = "../../modules/proxmox-vm"
  count  = var.worker_count

  vmid        = 121 + count.index
  hostname    = "k3s-worker-${count.index}"
  cores       = 2
  memory_mb   = 4096
  disk_gb     = 30
  ip_cidr     = "192.168.0.${81 + count.index}/24"
  gateway     = "192.168.0.1"
  proxmox_node = var.proxmox_node
  storage     = "local-lvm"
  bridge      = "vmbr0"

  os_image_id    = proxmox_virtual_environment_download_file.ubuntu_24_04.id
  ssh_public_key = var.ssh_public_key

  teleport_join_token  = teleport_provision_token.vm_nodes.metadata[0].name
  teleport_auth_server = var.teleport_auth_server
  teleport_ca_pin      = var.teleport_ca_pin
  role                 = "k3s-worker"
}
