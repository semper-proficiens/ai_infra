terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.69"
    }
    teleport = {
      source  = "terraform.releases.teleport.dev/gravitational/teleport"
      version = "~> 16.0"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_url
  api_token = var.proxmox_api_token
  insecure  = true # self-signed cert on homelab

  ssh {
    agent = true
  }
}

provider "teleport" {
  addr        = var.teleport_proxy
  identity_file_base64 = var.teleport_identity_file_base64
}
