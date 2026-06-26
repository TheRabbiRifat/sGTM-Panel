# Infrastructure

## Layout

```
infra/
├── ansible/
│   ├── playbook-node.yml          # bootstrap a new node
│   └── roles/
│       ├── docker/                # install Docker
│       ├── traefik/               # install Traefik (runs on every master node)
│       └── node-agent/            # install + start the node agent
├── systemd/
│   └── hostaffin-node-agent.service
└── scripts/
    ├── one-liner-install.sh       # token-safe one-shot wrapper (recommended entry-point)
    ├── install-interactive.sh     # ASCII-UI wizard (timezone, DNS, mode, …)
    ├── install-yum.sh             # YUM-family installer (the canonical one)
    ├── uninstall-yum.sh           # YUM-family uninstaller
    ├── lib-ui.sh                  # shared ASCII UI helpers
    ├── lib-pm.sh                  # dnf/yum auto-detection helpers
    ├── bootstrap-node.sh          # quick local dev bootstrap
    ├── rotate-jwt.sh              # rotate JWT keypair
    └── backup.sh                  # nightly Postgres → S3 backup
```

## Bootstrap a production node

```bash
ansible-playbook -i inventory/prod \
  -e node_id=edge-fra-01 \
  -e node_api_key=... \
  -e control_plane_url=https://control-plane.hostaffin.com \
  infra/ansible/playbook-node.yml
```

## Local dev

```bash
./infra/scripts/bootstrap-node.sh
```

This initializes a single-node Swarm, creates the `hostaffin_edge` overlay
network, and starts the node-agent under systemd.

## Supported operating systems

Both `install-interactive.sh` and `install-yum.sh` accept **any
YUM-family distro** and auto-detect whether to use `dnf` (modern) or
`yum` (legacy). The shared helper `lib-pm.sh` provides `pm_install`,
`pm_remove`, `pm_addrepo`, and `pm_repo_install` so the rest of the
scripts do not need to know which binary is present.

| Distro                  | Versions         | Package manager |
| ----------------------- | ---------------- | --------------- |
| AlmaLinux               | 8, 9             | dnf             |
| Rocky Linux             | 8, 9             | dnf             |
| RHEL                    | 7, 8, 9          | yum (7) / dnf (8+) |
| CentOS Stream           | 8, 9             | dnf             |
| Oracle Linux            | 7, 8, 9          | yum (7) / dnf (8+) |
| Fedora                  | 36+              | dnf             |
| Amazon Linux            | 2, 2023          | yum (AL2) / dnf (AL2023) |

Force a specific package manager with `HOSTAFFIN_PM=dnf|yum` if the
auto-detect ever picks the wrong one (rare; mostly useful in chroots).

### Quick install

```bash
# Interactive wizard (recommended) — ASCII UI, prompts for everything
sudo ./infra/scripts/install-interactive.sh

# Direct, non-interactive — load secrets from a 0600 env-file, never
# pass tokens on the command line.
sudo set -a; source /etc/hostaffin/install.env; set +a
sudo -E ./infra/scripts/install-yum.sh \
  --mode local \
  --control-plane-url http://localhost:8080 \
  --non-interactive
```

### Token-safe one-liner

The `one-liner-install.sh` wrapper handles download, checksum
verification, env-file loading, and cleanup for you. Tokens live in
`/etc/hostaffin/install.env` (mode `0600`) — they never appear in
`ps`, `/proc/<pid>/cmdline`, or shell history.

```bash
# 1. Stage secrets (once per host)
sudo install -m 0600 /dev/null /etc/hostaffin/install.env
sudo vi /etc/hostaffin/install.env
#   HOSTAFFIN_MODE=local
#   HOSTAFFIN_GITHUB_TOKEN=ghp_...

# 2. Run the wrapper
sudo bash -c '
  tmp=$(mktemp -d) &&
  curl -fsSL --proto =https \
    https://raw.githubusercontent.com/TheRabbiRifat/sGTM-Panel/main/infra/scripts/one-liner-install.sh \
    -o "$tmp/wrap" &&
  bash "$tmp/wrap" --env-file /etc/hostaffin/install.env --yes
'
```

The wrapper refuses to run without `--env-file`, refuses any
`HOSTAFFIN_*` env-file whose mode isn't `0400` or `0600`, refuses any
variable that isn't `HOSTAFFIN_[A-Z0-9_]+`, and verifies the SHA-256
of every fetched script against an embedded manifest before executing.
See the [top-level README](../README.md#one-liner-recommended) for
the full set of wrapper flags and guarantees.