# Ubuntu 24.04 cloud image — downloaded once manually on the Proxmox host:
#   wget -O /var/lib/vz/template/iso/noble-server-cloudimg-amd64.img \
#     https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
#
# Referenced as a data source so Terraform does not try to re-download it
# (avoids needing Sys.Modify privilege on the download URL API endpoint).

data "proxmox_virtual_environment_file" "ubuntu_24_04" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.proxmox_node
  file_name    = "noble-server-cloudimg-amd64.img"
}

data "proxmox_virtual_environment_file" "ubuntu_24_04_ssj2" {
  provider     = proxmox.ssj2
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.proxmox_node_ssj2
  file_name    = "noble-server-cloudimg-amd64.img"
}
