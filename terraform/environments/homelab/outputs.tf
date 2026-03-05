output "k3s_control_ip" {
  description = "k3s control plane IP address"
  value       = module.k3s_control.ip_address
}

output "worker_ips" {
  description = "k3s worker node IP addresses"
  value       = [for w in module.k3s_workers : w.ip_address]
}

output "worker_count" {
  description = "Number of k3s worker nodes"
  value       = var.worker_count
}

output "runner_ip" {
  description = "GitHub runner LXC IP address"
  value       = module.runner.ip_address
}

output "bot_join_token" {
  description = "Join token name for tbot (infra-bot)"
  value       = teleport_bot.infra_bot.metadata[0].name
  sensitive   = true
}

output "lxc_join_token_name" {
  description = "Teleport provision token name for LXC nodes"
  value       = teleport_provision_token.lxc_nodes.metadata[0].name
}

output "vm_join_token_name" {
  description = "Teleport provision token name for VM nodes"
  value       = teleport_provision_token.vm_nodes.metadata[0].name
}
