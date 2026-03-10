# Proxmox
variable "proxmox_url" {
  description = "Proxmox API endpoint, e.g. https://192.168.0.69:8006"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API token, format: user@realm!token-id=secret"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "test"
}

# Teleport
variable "teleport_auth_server" {
  description = "Teleport auth server for node joining, e.g. 192.168.0.199:3025"
  type        = string
  default     = "192.168.0.199:3025"
}

variable "teleport_ca_pin" {
  description = "Teleport CA pin (sha256:...)"
  type        = string
  default     = "sha256:2b82ae8b8f92835b2f2886ad25537547ce7a59e79cdbacd4be311f4df41bb13b"
}

# Teleport provision tokens — create once with:
#   tctl tokens add --type=node --ttl=87600h
# Then paste the token value here (gitignored in terraform.tfvars)
variable "vm_join_token" {
  description = "Teleport node join token for VMs (k3s control + workers)"
  type        = string
  sensitive   = true
}

variable "lxc_join_token" {
  description = "Teleport node join token for LXC containers (runner)"
  type        = string
  sensitive   = true
}

# SSH
variable "ssh_public_key" {
  description = "SSH public key to inject into all nodes"
  type        = string
}

# k3s scaling — workers on ssj1
variable "worker_count" {
  description = "Number of k3s worker nodes on ssj1"
  type        = number
  default     = 1
}

# ssj2
variable "proxmox_url_ssj2" {
  description = "Proxmox API endpoint for ssj2, e.g. https://192.168.0.84:8006"
  type        = string
  default     = "https://192.168.0.84:8006"
}

variable "proxmox_api_token_ssj2" {
  description = "Proxmox API token for ssj2, format: user@realm!token-id=secret"
  type        = string
  sensitive   = true
}

variable "proxmox_node_ssj2" {
  description = "Proxmox node name for ssj2"
  type        = string
  default     = "test2"
}
