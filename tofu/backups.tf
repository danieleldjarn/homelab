resource "proxmox_backup_job" "audiobookshelf" {
  id       = "backup-audiobookshelf"
  schedule = "04:00"
  storage  = "tiphares_backups"
  node     = var.target_node

  vmid = [tostring(proxmox_virtual_environment_container.audiobookshelf.vm_id)]

  mode           = "snapshot"
  compress       = "zstd"
  enabled        = true
  notes_template = "{{guestname}}_{{vmid}}"

  prune_backups = {
    "keep-daily"   = "7"
    "keep-weekly"  = "4"
    "keep-monthly" = "3"
  }
}
