# Manual configuration outside OpenTofu (container 110 — audiobookshelf)

**Why this file exists:** a few operations require the *real* `root@pam` user.
An API token cannot perform them — not even a token belonging to `root@pam`,
because Proxmox checks `$authuser eq 'root@pam'` and a token's authuser is
`root@pam!tokenname`. We chose to keep OpenTofu on the scoped `tofu@pve` token
and do these steps by hand instead.

`tofu/main.tf` therefore carries:

```hcl
lifecycle {
  ignore_changes = [features, mount_point]
}
```

so OpenTofu never tries to revert them.

**If container 110 is ever destroyed and recreated, replay everything below.**

---

## 1. Host: SMB mount of the Unraid audiobooks share

Runs on the Proxmox host (`172.16.0.166`), as root.

Credentials file (root-only; the password is NOT in git):

```bash
mkdir -p /etc/credentials
cat > /etc/credentials/unraid-audiobooks <<'EOF'
username=audiobookshelf
password=<the unraid smb password>
EOF
chmod 600 /etc/credentials/unraid-audiobooks
```

Mount point and `/etc/fstab` line:

```bash
mkdir -p /mnt/nas/audiobooks
```

```
//172.16.0.100/audiobooks  /mnt/nas/audiobooks  cifs  credentials=/etc/credentials/unraid-audiobooks,uid=100999,gid=100991,file_mode=0664,dir_mode=0775,iocharset=utf8,vers=3.0,_netdev,nofail  0  0
```

Verify without rebooting:

```bash
mount -a && findmnt /mnt/nas/audiobooks
```

### The uid/gid numbers matter

Audiobookshelf runs inside the container as `uid=999 gid=991`. The container is
**unprivileged**, so container UIDs are shifted by 100000 on the host:

```
container 999  ==  host 100999
container 991  ==  host 100991
```

Mounting the share with `uid=100999,gid=100991` forces every file to appear
owned by `audiobookshelf:audiobookshelf` *inside* the container — no chown on
the NAS, no `lxc.idmap` needed.

**If the audiobookshelf package ever changes its uid/gid, these numbers must be
updated too.** Check with `id audiobookshelf` inside the container.

`_netdev,nofail` are required: without `nofail`, an unreachable NAS can block
the host's boot.

---

## 2. Container: nesting feature flag

Debian 13 ships systemd 257, which needs to mount `/tmp`, `/run/lock` and
`/dev/mqueue`. Without `nesting=1` the AppArmor profile denies those and the
container boots `degraded` with three failed mount units.

`nesting` alone only needs `VM.Allocate` (which our scoped token has), but the
bpg provider serialises all four feature flags together and `fuse`/`keyctl`/
`mknod` are root@pam-only — so the provider's `features` block always 403s.
Setting it via the raw API works fine with the scoped token:

```bash
export PROXMOX_VE_API_TOKEN='tofu@pve!tofu=<secret>'

curl -k -X PUT -H "Authorization: PVEAPIToken=${PROXMOX_VE_API_TOKEN}" \
  "https://172.16.0.166:8006/api2/json/nodes/proxmox/lxc/110/config" \
  --data-urlencode 'features=nesting=1'

curl -k -X POST -H "Authorization: PVEAPIToken=${PROXMOX_VE_API_TOKEN}" \
  "https://172.16.0.166:8006/api2/json/nodes/proxmox/lxc/110/status/reboot"
```

Verify: `ssh root@<ct-ip> 'systemctl is-system-running'` → `running`, and
`systemctl --failed` → 0 units.

---

## 3. Container: bind mount of the NAS share

Bind mounts are root@pam-only with no exception (Proxmox source: *"mount point
type ... is only allowed for root@pam"*), so this must run as root **on the
host**, not through the API:

```bash
pct set 110 -mp0 /mnt/nas/audiobooks,mp=/audiobooks
pct reboot 110
```

Verify from a workstation:

```bash
ssh root@<ct-ip> 'ls -la /audiobooks'
ssh root@<ct-ip> 'runuser -u audiobookshelf -- touch /audiobooks/.t && rm /audiobooks/.t && echo OK'
```

Owner must show `audiobookshelf audiobookshelf` — not `nobody` or bare numbers.
(Note: `sudo` is not installed in the container; use `runuser`.)

### Known caveat: boot ordering

The bind mount is established when the container **starts**. If the Proxmox host
boots while the NAS is unreachable, the container gets an empty directory and
will not notice the share appearing later. Fix: `pct reboot 110` once the NAS is
up. Symptom: Audiobookshelf shows an empty library after a power cut.

---

## How to eliminate these manual steps later

- **Switch the provider to `root@pam` username/password auth**
  (`PROXMOX_VE_USERNAME` / `PROXMOX_VE_PASSWORD`). Both the `features` block and
  a `mount_point` block would then work declaratively and this whole file could
  be deleted. Cost: the root password lives in an env var and cannot be revoked
  independently like a token.
- **Let Ansible manage the Proxmox host** (add it to the inventory):
  `ansible.posix.mount` for the fstab entry, plus `pct set` for the bind mount,
  running as real root over SSH key auth. Keeps the scoped token.
- **Upstream fix**: if the bpg provider ever serialises feature flags
  individually, the `nesting` workaround becomes unnecessary. See
  `unifi_via_opentofu.md` for the related habit of tracking provider PRs.
