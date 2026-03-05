output "vmid" {
  description = "Proxmox VM ID"
  value       = proxmox_virtual_environment_vm.this.id
}

output "ip_address" {
  description = "VM IP address (without CIDR)"
  value       = split("/", var.ip_cidr)[0]
}

output "hostname" {
  description = "VM hostname"
  value       = var.hostname
}
