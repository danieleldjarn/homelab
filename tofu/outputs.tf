output "audiobookshelf_ipv4" {
  description = "IPv4 addresses reported by the container (per interface)"
  value       = proxmox_virtual_environment_container.audiobookshelf.ipv4
}
