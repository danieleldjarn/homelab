resource "proxmox_virtual_environment_container" "audiobookshelf" {
  node_name     = var.target_node
  vm_id         = 110
  unprivileged  = true
  started       = true
  start_on_boot = true

  operating_system {
    template_file_id = "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
    type             = "debian"
  }

  lifecycle {
    ignore_changes = [features, mount_point]
  }

  cpu {
    cores = 2
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-zfs"
    size         = 5
  }

  network_interface {
    name   = "eth0"
    bridge = "vmbr0"
  }

  initialization {
    hostname = "audiobookshelf"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      keys = [trimspace(file(pathexpand(var.ssh_public_key_path)))]
    }
  }

  tags = ["tofu", "audiobookshelf"]
}
