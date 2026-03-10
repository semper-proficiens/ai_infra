terraform {
  required_version = ">= 1.6.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.69"
    }
  }

  backend "s3" {
    bucket = "terraform-state"
    key    = "homelab/terraform.tfstate"
    region = "us-east-1"

    endpoints = {
      s3 = "http://minio.starstalk.internal:31423"
    }

    # MinIO-specific: disable AWS-specific validation
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    use_path_style              = true
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

# ssj2 provider alias (192.168.0.84)
provider "proxmox" {
  alias     = "ssj2"
  endpoint  = var.proxmox_url_ssj2
  api_token = var.proxmox_api_token_ssj2
  insecure  = true

  ssh {
    agent    = true
    username = "root"
  }
}
