output "k3s_control_ip" {
  description = "k3s control plane IP address"
  value       = module.k3s_control.ip_address
}

output "worker_ips" {
  description = "k3s worker node IP addresses (ssj1)"
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
