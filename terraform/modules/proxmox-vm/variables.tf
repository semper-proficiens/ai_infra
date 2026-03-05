variable "vmid" {
  description = "Proxmox VM ID"
  type        = number
}

variable "hostname" {
  description = "VM hostname"
  type        = string
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "Memory in MB"
  type        = number
  default     = 2048
}

variable "disk_gb" {
  description = "Root disk size in GB"
  type        = number
  default     = 20
}

variable "ip_cidr" {
  description = "IP address with CIDR prefix, e.g. 192.168.0.80/24"
  type        = string
}

variable "gateway" {
  description = "Default gateway IP"
  type        = string
  default     = "192.168.0.1"
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "test"
}

variable "storage" {
  description = "Storage pool for VM disk"
  type        = string
  default     = "local-lvm"
}

variable "bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

variable "os_image_id" {
  description = "Proxmox file ID for the cloud image (from images.tf download)"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key to inject into root account"
  type        = string
}

variable "teleport_join_token" {
  description = "Teleport provision token name for this node"
  type        = string
}

variable "teleport_auth_server" {
  description = "Teleport auth server address, e.g. 192.168.0.199:3025"
  type        = string
}

variable "teleport_ca_pin" {
  description = "Teleport CA pin (sha256:...)"
  type        = string
}

variable "role" {
  description = "Node role label (e.g. k3s-control, k3s-worker)"
  type        = string
}
