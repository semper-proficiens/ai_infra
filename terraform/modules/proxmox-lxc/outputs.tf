output "vmid" {
  description = "Proxmox container ID"
  value       = proxmox_virtual_environment_container.this.id
}

output "ip_address" {
  description = "Container IP address (without CIDR)"
  value       = split("/", var.ip_cidr)[0]
}

output "hostname" {
  description = "Container hostname"
  value       = var.hostname
}
