terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.69"
    }
  }
}

locals {
  cloud_init_content = templatefile("${path.module}/cloud-init.yaml.tpl", {
    hostname             = var.hostname
    teleport_join_token  = var.teleport_join_token
    teleport_auth_server = var.teleport_auth_server
    teleport_ca_pin      = var.teleport_ca_pin
    role                 = var.role
    ssh_public_key       = var.ssh_public_key
  })
}

resource "proxmox_virtual_environment_file" "cloud_init" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = var.proxmox_node

  source_raw {
    data      = local.cloud_init_content
    file_name = "${var.hostname}-cloud-init.yaml"
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
    file_format  = "raw"
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

    datastore_id      = "local"
    user_data_file_id = proxmox_virtual_environment_file.cloud_init.id
  }

  on_boot = true

  tags = ["terraform", var.role]
}
