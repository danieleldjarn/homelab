# Idea: Manage UniFi through OpenTofu

**Status:** parked (2026-07-16) — revisit after Audiobookshelf (tofu + Ansible) is done.

## The insight

Managing UniFi via OpenTofu does NOT create a "second place" to manage the network.
The provider writes through the UniFi controller's API — the same controller the
console displays — so the console keeps full oversight while git gains the history:

```
git repo (source of truth) ──tofu──► UniFi controller ◄──── UniFi console (live view)
```

## Providers (checked 2026-07-16, both actively maintained)

| Provider | Version | Notes |
|---|---|---|
| `ubiquiti-community/unifi` | 0.55.0 | successor of abandoned `paultyng/unifi` |
| `filipowm/unifi` | 1.1.0 | alternative fork, also active |

Old tutorials reference `paultyng/unifi` — abandoned, ignore them.

## What it can manage

- Networks / VLANs, WiFi SSIDs
- Firewall rules, port forwarding, static routes
- User groups
- **`unifi_user`** — client entries with fixed IPs, i.e. DHCP reservations as code

## The elegant endgame

The LXC's MAC address is a computed attribute of the Proxmox resource, so a
reservation can be wired to the container automatically — one `apply` creates the
container in Proxmox AND its fixed IP in UniFi:

```hcl
resource "unifi_user" "audiobookshelf" {
  mac      = proxmox_virtual_environment_container.audiobookshelf.network_interface[0].mac_address # verify exact attribute path
  name     = "audiobookshelf"
  fixed_ip = "172.16.0.110"
}
```

## Prerequisites / open questions

- Needs a local admin account (or API key) on the UDR for the provider — figure out
  least-privilege options; ties into the secrets management plan
  (see `secrets_management.md`).
- UniFi's local DNS registers DHCP client hostnames — this project likely also
  solves the "better local hostnames" wish.
- Decide which provider fork to use (compare resource coverage when picking this up).

## Related parked ideas

- Better local hostnames / local DNS (partially solved by this)
- Proper TLS cert for Proxmox (so `insecure = true` can be dropped)
- Migrate manually-clicked UniFi config into code once provider is adopted
