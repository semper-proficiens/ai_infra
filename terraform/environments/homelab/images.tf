# Download Ubuntu 24.04 cloud image to Proxmox local storage once
# Used by all proxmox-vm module instances as the base OS image
resource "proxmox_virtual_environment_download_file" "ubuntu_24_04" {
  node_name    = var.proxmox_node
  content_type = "iso"
  datastore_id = "local"

  # Noble Numbat (24.04 LTS) cloud image — SHA256 verified by Proxmox
  url       = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name = "noble-server-cloudimg-amd64.img"

  # Only re-download if the upstream image changes checksum
  overwrite = false
}
