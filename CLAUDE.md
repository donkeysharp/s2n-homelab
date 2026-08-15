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

Outside the fleet: `palantir`, a public VPS at `palantir.s2n.donkeysharp.xyz` (user `ansible`, no `.lan` name). It is not in `s2n` and gets none of the fleet-wide roles — it exists only as the public end of the site-to-site VPN.

Inventory groups (`inventory/hosts.yml`): `x86_64`, `raspberry_pi`, `dell`, `database`, `s2n` (= x86_64 + raspberry_pi, covers all 10), `k3s_cluster` (`server` + `agent`), and `vpn` (`vpn_server` = palantir, `vpn_client` = galadriel). Dell hosts are members of both `dell` and `x86_64`.

## Layout

- `playbooks/` — `base-setup.yml` (one-time bootstrap: creates `ansible` user + SSH key), `homelab.yml` (common role on `s2n`), `database.yml` (Postgres on `galadriel`), `k3s_cluster.yml` / `k3s_reset.yml` (k3s via upstream collection), `site-to-site-vpn.yml` (WireGuard, the public HAProxy, and the gateway NAT rule), `debug.yml`.
- `roles/common` — base packages + tmux config; `i8kutils` on Dell only.
- `roles/docker` — Docker CE install. `docker_arch` defaults to `amd64` (only x86_64 use case needed).
- `roles/postgresql` — `postgres:18` via docker-compose; creates per-app DBs/users from vault secrets.
- `roles/wireguard` — one tunnel endpoint, server or client per `wireguard_mode`. Generates its keypair once and installs `iptables` + `iptables-persistent`.
- `roles/l4_proxy` — HAProxy in TCP mode on `palantir`, from the official `haproxy.debian.net` repo (major version pinned by `l4_proxy_version`), not Debian's. The config is fixed — 443 and 80 forwarded to Traefik with PROXY protocol v2 — and `l4_proxy_servers` is the only input.
- `group_vars/` — `database.yml` holds vault-encrypted DB passwords + `additional_databases` (k3s, hedgedoc). `k3s_cluster.yml` wires k3s to the external Postgres datastore.
- `inventory/host_vars/` — per-host vars (`palantir.yml`, `galadriel.yml` carry the WireGuard addresses and peer lists).

### Where variables have to live

Root `group_vars/` is **not** auto-loaded. Ansible only picks up `group_vars/`/`host_vars/` sitting next to the inventory file (`inventory/`) or next to the playbook (`playbooks/`), and the repo root is neither — which is why every playbook pulls what it needs with `vars_files: ../group_vars/x.yml`. Per-host vars have no such escape hatch (`vars_files` is play-scoped, not per-host), so they must go in `inventory/host_vars/<host>.yml`. Files placed in a root `host_vars/` are silently ignored.
- `k8s-manifests/` — `hello-world` (http-echo) deploy/service/ingress, used to validate Traefik.
  - New Kubernetes manifests always go into a `draft/` subdirectory of where they will eventually live — e.g. `k8s-manifests/cluster/cert-manager/draft/`. They are reviewed and copied out by hand. Never write new manifests directly to their final path. The main reason for this is that, as this is a project I use to learn different things and although documentation is read, there is a cognitive debt on letting AI do everything for me in the sense that even though I review, I prefer to go by detail by copying it. Based on this [article](https://explainx.ai/blog/cognitive-debt-retype-llm-code-august-2026) mainly for me to experimient.

## k3s notes

- `galadriel` is the single control-plane node (tainted `NoSchedule`), using external PostgreSQL as the datastore (`--datastore-endpoint=postgres://...@galadriel.lan:5432/k3s`).
- Ships Traefik as the default ingress controller plus klipper-lb (ServiceLB), so ports 80/443 answer on every node IP. An `Ingress` with a `host:` rule routes by hostname. To reach by name, add DNS on OpenWrt (or a client `/etc/hosts` / `Host:` header) pointing the hostname at any node IP.
- When resetting the cluster, also wipe the k3s Postgres database — otherwise stale state breaks the new cluster.
- Do NOT set a custom `token` var in `group_vars/k3s_cluster.yml` — it caused node-join failures. Leave it unset.
- RPi nodes need cgroups enabled in `cmdline.txt` (`cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory`). See `notes/todo.md`.

## Site-to-site VPN

- Tunnel `wg0` on `10.10.10.0/24` — `palantir` is `.1` (server, listens on UDP 51820), `galadriel` is `.2` (client, keepalive 25 since it is behind NAT).
- `galadriel` is the subnet gateway for the LAN `192.168.175.0/24`: palantir's peer `AllowedIPs` carries that CIDR, and galadriel forwards plus MASQUERADEs it so replies come back through the tunnel instead of to the OpenWrt router. The NAT rule lives in `playbooks/site-to-site-vpn.yml`, tagged with the iptables comment `site-to-site subnet gateway`.
- Both ends must stay in the **same play**. Each host generates its keypair, publishes the public key as a fact, and only then renders its config, reading the peer's key from `hostvars`. Splitting into per-mode plays, adding `serial:`, or `--limit`-ing one end breaks the exchange — the role asserts instead of writing a config with a missing peer.
- `palantir` also runs HAProxy (`roles/l4_proxy`) as the public entry point: 80/443 are load balanced over the tunnel to Traefik on the k3s node IPs, listed in `inventory/host_vars/palantir.yml`.
- Private keys are generated on the host with `creates:` and never regenerated or copied to the control node's fact cache. A peer can also be given a literal `public_key` instead of a `host`, for endpoints Ansible does not manage.

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

# Site-to-site VPN (both ends, single run)
ansible-playbook playbooks/site-to-site-vpn.yml

# Target subsets
ansible-playbook playbooks/homelab.yml --limit raspberry_pi
ansible-playbook playbooks/homelab.yml --limit frodo --check
```

## Conventions & preferences

- When adding code or content, comment only the important, non-obvious parts — do not comment everything. No emojis.
- Prefer reading files over running shell/git commands to inspect state.
- `env/` is a committed Python virtualenv (Ansible + deps) — ignore it; it is not project code.
- PostgreSQL on `galadriel` is a deliberate single point of failure — "rebuild if it dies," backups deferred. Do not over-engineer HA unless asked.
