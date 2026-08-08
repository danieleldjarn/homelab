variable "proxmox_endpoint" {
  description = "Proxmox API endpoint (web UI URL on port 8006)"
  type        = string
  default     = "https://172.16.0.166:8006/"
}

variable "target_node" {
  description = "Proxmox node to create the container on"
  type        = string
  default     = "proxmox"
}

variable "ssh_public_key_path" {
  description = "Public key injected into the container for Ansible SSH access"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
