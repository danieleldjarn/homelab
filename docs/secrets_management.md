# Infisical Self-Hosting + Off-Site Backup Plan

_A reference plan for running self-hosted Infisical on the homelab (Proxmox + Unraid), with a free backup/restore strategy. Not implemented yet — this is the design to work from later._

---

## 1. Goal

Run Infisical (secrets manager) self-hosted for free, with resilience so that if a box dies, the secrets are recoverable. This document covers the licensing reality, the deployment shape, the backup strategy, and the exact restore procedure — including the one gotcha that makes an untested backup useless.

---

## 2. Licensing reality (what's actually free)

- The **core Infisical platform is MIT-licensed and free to self-host with unlimited users.** This is different from the *cloud* free tier, which caps at 5 identities — the self-hosted community edition has no such cap.
- Paid enterprise features require a license key that phones home to Infisical's license server. If it expires, the instance keeps running but EE features get disabled.
- **Paywalled (EE) features** — not needed for a homelab: SAML SSO, advanced RBAC, dynamic secrets, approval workflows, audit-log retention, and **built-in replication**.
- **Free core gives you:** the secret store, projects/environments, all integrations (CLI, Docker, K8s, Terraform, Ansible, GitHub Actions, etc.), secret referencing, and secret scanning. For personal use, that's the whole product.

> Note: the *paid* self-hosted license terms forbid air-gapping the instance without permission (so they can bill on usage). This is a paid-tier constraint only — the MIT core doesn't phone home and has no such restriction.

---

## 3. Deployment shape

Infisical's server is **stateless — all state lives in Postgres.** This single fact drives the entire backup/restore and "sync" strategy.

Standard stack:

- **Infisical** (single Docker image — bundles backend API + web UI)
- **PostgreSQL** (the database — the only thing that actually holds your data)
- **Redis** (caching / background jobs)

A standalone single-Docker-image deployment option also exists if you want to keep it lighter.

On first boot: create the admin account, then **download the Emergency Kit PDF** shown during setup and store it securely — it's a recovery path if you get locked out.

On Unraid, a Compose stack (Infisical + Postgres + Redis) behind the existing reverse proxy is the natural fit.

---

## 4. The "sync between two instances" question — resolved

There is **no bidirectional, two-independent-instances-that-sync-to-each-other mode**, and you wouldn't want one. "Syncing two instances" really means **replicating one Postgres DB to the other**, with an Infisical app in front of each. Two Infisical apps each pointed at their own separate DB don't know about each other.

Options considered:

| Approach | Free? | Notes |
|---|---|---|
| **Infisical built-in replication** | ❌ Paid (EE) | Primary/secondary (1:N) async Postgres streaming replication; secondaries proxy writes to primary; sub-second lag. Turnkey but requires an enterprise license. |
| **DIY Postgres streaming replication** | ✅ Free | Set up vanilla Postgres streaming replication yourself between the two hosts. Same active/standby result, no Infisical paid layer. Requires identical Infisical versions on both; migrations run on primary only. |
| **Active + cold/warm standby via backups** | ✅ Free | One active instance; the other box holds regular `pg_dump` restores. Simple; a few-minutes-stale copy. **← Recommended for homelab.** |

**Avoid multi-master** (both nodes writable, syncing both ways). That's a conflict/corruption trap, not a feature.

### Recommendation
Unless automatic failover is specifically needed: **active-on-Proxmox + scheduled `pg_dump` restored to Unraid.** Resilience without running two databases in lockstep or matching versions religiously. If a live standby is genuinely wanted, the free route is self-managed Postgres streaming replication — nothing inside Infisical.

---

## 5. Backup strategy (the important part)

All state is in Postgres, and **secrets are stored encrypted** — so a DB dump contains ciphertext, not plaintext.

**⚠️ The DB dump alone is NOT enough to recover.** Infisical decrypts using `ENCRYPTION_KEY` (and `AUTH_SECRET`) from its environment config — these live in the compose/env file, **not** in the database. Restore the DB with a *freshly generated* `ENCRYPTION_KEY` and nothing decrypts → locked out. Same failure mode as losing the key entirely.

### A genuinely restorable backup needs THREE things together:

1. **The `pg_dump` file** — the encrypted data.
2. **The `ENCRYPTION_KEY` and `AUTH_SECRET` values** — the thing that decrypts it.
3. **The Emergency Kit PDF** from initial setup.

### Where to store each

- **`pg_dump` file:** on Unraid, then shipped off-site (Backblaze B2, rsync.net, or a second location) using restic or Kopia — likely pointed at the existing Unraid backup pipeline.
- **`ENCRYPTION_KEY` / `AUTH_SECRET`:** store **independently of the dump** — in your actual password manager. This way a compromise of the Unraid backup doesn't hand someone both halves (encrypted data + the key to it).
- **Emergency Kit PDF:** secure storage alongside the keys.

---

## 6. Restore / rebuild procedure

Rebuild flow (e.g. rebuilding the Proxmox server from the Unraid-held backup):

1. **Stand up a fresh Postgres** on the rebuilt box (empty database).
2. **Restore the dump:**
   - `psql` for a plain-SQL dump, or
   - `pg_restore` if the dump was `pg_dump -Fc` (custom format).
3. **Bring up the Infisical container** pointed at the restored DB — **using the original `ENCRYPTION_KEY` and `AUTH_SECRET`** (this is the step that fails silently if you forget).
4. Infisical comes back with all secrets, projects, users, and history intact.

### Restore compatibility notes

- **Match the Postgres major version** between backup and restore target where possible (PG16 → PG16 is painless; large version jumps need care).
- **Match the Infisical version** too — a newer app expecting a migrated schema against an older dump (or vice versa) can misbehave. Pin both in the compose file.

---

## 7. Test the backup before relying on it

An untested backup isn't a backup — and this one has a hidden second ingredient (the encryption key) that makes testing especially worth it.

**Dry run:**

1. Restore the dump into a throwaway Postgres.
2. Point a scratch Infisical container at it **with the real encryption key**.
3. Confirm you can log in and read a secret.

If that works, the backup is proven end-to-end.

---

## 8. Quick checklist

- [ ] Deploy Infisical + Postgres + Redis (Compose) on the chosen active host (Proxmox)
- [ ] Save the Emergency Kit PDF from first-boot setup
- [ ] Record `ENCRYPTION_KEY` + `AUTH_SECRET` in password manager
- [ ] Set up scheduled `pg_dump` (custom format, `-Fc`)
- [ ] Ship dumps to Unraid, then off-site via restic/Kopia
- [ ] Decide: cold-standby (backups only) vs warm-standby (Postgres streaming replication)
- [ ] Do one full dry-run restore with the real key to verify
- [ ] Document the pinned Postgres + Infisical versions

---

## 9. Open decisions for later

- **Failover vs. "not gone":** genuine automatic failover → self-managed Postgres streaming replication. Just "secrets survive a dead box" → cold-standby + backups (simpler, recommended).
- **Off-site target:** Backblaze B2 / rsync.net / second physical location.
- **Backup tool:** restic vs Kopia (either fine; whichever the existing Unraid pipeline already uses).
