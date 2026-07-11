# CLAUDE.md

Ansible project managing the **S2N homelab** — a fleet of home servers. "s2n" = **S**ergio, **N**atalia, **N**ami (the owner's family). All hosts are named after Lord of the Rings characters.

## Fleet (10 hosts, 3 hardware tiers)

Hostnames resolve via `.lan` through an OpenWrt router (local DNS — nothing to manage here).

| Host | Arch | Brand | Notes |
|------|------|-------|-------|
| `frodo`, `samwise` | x86_64 | GMK mini-PC | k3s agents |
| `galadriel` | x86_64 | Dell OptiPlex | k3s server + PostgreSQL host |
| `elrond`, `arwen` | x86_64 | Dell OptiPlex | k3s agents; get `i8kutils` |
| `aragorn`, `legolas`, `gimli`, `pippin`, `merry` | ARM | RPi 3B | k3s agents |

Inventory groups (`inventory/hosts.yml`): `x86_64`, `raspberry_pi`, `dell`, `database`, `s2n` (= x86_64 + raspberry_pi, covers all 10), and `k3s_cluster` (`server` + `agent`). Dell hosts are members of both `dell` and `x86_64`.

## Layout

- `playbooks/` — `base-setup.yml` (one-time bootstrap: creates `ansible` user + SSH key), `homelab.yml` (common role on `s2n`), `database.yml` (Postgres on `galadriel`), `k3s_cluster.yml` / `k3s_reset.yml` (k3s via upstream collection), `debug.yml`.
- `roles/common` — base packages + tmux config; `i8kutils` on Dell only.
- `roles/docker` — Docker CE install. `docker_arch` defaults to `amd64` (only x86_64 use case needed).
- `roles/postgresql` — `postgres:18` via docker-compose; creates per-app DBs/users from vault secrets.
- `group_vars/` — `database.yml` holds vault-encrypted DB passwords + `additional_databases` (k3s, hedgedoc). `k3s_cluster.yml` wires k3s to the external Postgres datastore.
- `k8s-manifests/` — `hello-world` (http-echo) deploy/service/ingress, used to validate Traefik.

## k3s notes

- `galadriel` is the single control-plane node (tainted `NoSchedule`), using external PostgreSQL as the datastore (`--datastore-endpoint=postgres://...@galadriel.lan:5432/k3s`).
- Ships Traefik as the default ingress controller plus klipper-lb (ServiceLB), so ports 80/443 answer on every node IP. An `Ingress` with a `host:` rule routes by hostname. To reach by name, add DNS on OpenWrt (or a client `/etc/hosts` / `Host:` header) pointing the hostname at any node IP.
- When resetting the cluster, also wipe the k3s Postgres database — otherwise stale state breaks the new cluster.
- Do NOT set a custom `token` var in `group_vars/k3s_cluster.yml` — it caused node-join failures. Leave it unset.
- RPi nodes need cgroups enabled in `cmdline.txt` (`cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory`). See `notes/todo.md`.

## Secrets

- Ansible Vault. Password file is `.vault-password` (git-ignored, never committed). Pass `--vault-password-file .vault-password` to playbooks touching secrets.
- `pub_keys/*.pub` and `.vault-password` are git-ignored. Only vault ciphertext lives in the repo.
- Encrypt a value: `ansible-vault encrypt_string --vault-password-file .vault-password "secret" --name secret_name`.

## Common commands

```bash
# Common setup across the fleet
ansible-playbook playbooks/homelab.yml

# Postgres
ansible-playbook --vault-password-file .vault-password playbooks/database.yml

# k3s install / reset
ansible-playbook -i inventory/hosts.yml --vault-password-file .vault-password playbooks/k3s_cluster.yml
ansible-playbook -i inventory/hosts.yml --vault-password-file .vault-password playbooks/k3s_reset.yml

# Target subsets
ansible-playbook playbooks/homelab.yml --limit raspberry_pi
ansible-playbook playbooks/homelab.yml --limit frodo --check
```

## Conventions & preferences

- When adding code or content, comment only the important, non-obvious parts — do not comment everything. No emojis.
- Prefer reading files over running shell/git commands to inspect state.
- `env/` is a committed Python virtualenv (Ansible + deps) — ignore it; it is not project code.
- PostgreSQL on `galadriel` is a deliberate single point of failure — "rebuild if it dies," backups deferred. Do not over-engineer HA unless asked.
