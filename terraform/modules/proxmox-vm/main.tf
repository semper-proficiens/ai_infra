terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.69"
    }
  }
}


resource "proxmox_virtual_environment_vm" "this" {
  node_name = var.proxmox_node
  vm_id     = var.vmid
  name      = var.hostname

  agent {
    enabled = true
  }

  cpu {
    cores = var.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = var.storage
    file_id      = var.os_image_id
    interface    = "virtio0"
    size         = var.disk_gb
    discard      = "on"
  }

  network_device {
    bridge = var.bridge
    model  = "virtio"
  }

  initialization {
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

  on_boot = true

  tags = ["terraform", var.role]
}
