# homelab

Infrastructure as code for my home server. OpenTofu (`tofu/`) provisions
containers and VMs on Proxmox; Ansible (`ansible/`) configures what runs inside
them.

Currently running:

- **Audiobookshelf** — LXC 110, audio library bind-mounted from the Unraid NAS

## Todo

- [ ] Set up a VM with Docker
- [ ] Set up Grafana for monitoring servers
- [ ] Set up local DNS records for services and servers

## Notes and parked ideas

See `docs/` — manual configuration that lives outside IaC and why, plus ideas
not yet started (managing UniFi with OpenTofu, secrets management).
