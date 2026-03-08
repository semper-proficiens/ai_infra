terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.69"
    }
  }
}


resource "proxmox_virtual_environment_container" "this" {
  node_name = var.proxmox_node
  vm_id     = var.vmid

  initialization {
    hostname = var.hostname

    ip_config {
      ipv4 {
        address = var.ip_cidr
        gateway = var.gateway
      }
    }

    user_account {
      keys = [var.ssh_public_key]
    }
  }

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.storage
    size         = var.disk_gb
  }

  network_interface {
    name   = "eth0"
    bridge = var.bridge
  }

  operating_system {
    template_file_id = var.template
    type             = "ubuntu"
  }

  # Enable nesting to allow Docker inside the LXC (required for CI build runners)
  dynamic "features" {
    for_each = var.enable_nesting ? [1] : []
    content {
      nesting = true
    }
  }

  start_on_boot = true
  started       = true

  tags = ["terraform", var.role]

  # Ignore fields that differ on imported existing containers and cannot be
  # changed in-place (would force destroy+recreate of a live container).
  lifecycle {
    ignore_changes = [
      operating_system,  # template_file_id only used at creation time
      initialization[0].user_account,  # SSH keys baked in at creation, not updatable
      unprivileged,      # set at creation, cannot change without recreate
      disk[0].size,      # actual disk may differ; resize handled out-of-band
    ]
  }
}
