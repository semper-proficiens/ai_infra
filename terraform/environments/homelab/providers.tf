terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.69"
    }
  }
}

# Default provider = ssj1 (192.168.0.69)
provider "proxmox" {
  endpoint  = var.proxmox_url
  api_token = var.proxmox_api_token
  insecure  = true # self-signed cert on homelab

  ssh {
    agent    = true
    username = "root"
  }
}
