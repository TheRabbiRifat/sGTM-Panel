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
    ├── installer.sh               # unified installer: install | uninstall | interactive | health-check
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

`installer.sh` accepts **any YUM-family distro** and auto-detects
whether to use `dnf` (modern) or `yum` (legacy). Internal helpers
provide `pm_install`, `pm_remove`, `pm_addrepo`, and `pm_repo_install`
so the rest of the script does not need to know which binary is
present.

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

`installer.sh` has four subcommands:

| Subcommand      | Purpose                                                     |
| --------------- | ----------------------------------------------------------- |
| `install`       | non-interactive install (default mode)                      |
| `uninstall`     | reverse the install; `--purge` removes data + config too    |
| `interactive`   | full-screen ASCII wizard for first-time installs            |
| `health-check`  | verify that the install is healthy and reachable            |
| `help`          | show all flags, env-vars, and examples                      |

```bash
# Interactive wizard (recommended for first-time installs)
sudo ./infra/scripts/installer.sh interactive

# Direct, non-interactive — load secrets from a 0600 env-file, never
# pass tokens on the command line.
sudo set -a; source /etc/hostaffin/install.env; set +a
sudo -E ./infra/scripts/installer.sh install \
  --mode local \
  --control-plane-url http://localhost:8080 \
  --non-interactive

# Uninstall (stops services + removes containers, keeps data)
sudo ./infra/scripts/installer.sh uninstall --mode local

# Full purge (irreversible — type DELETE to confirm)
sudo ./infra/scripts/installer.sh uninstall --mode local --purge

# Health check
sudo ./infra/scripts/installer.sh health-check
```

### Token-safe one-liner

The installer is token-safe by design. Tokens live in
`/etc/hostaffin/install.env` (mode `0600`) — they never appear in
`ps`, `/proc/<pid>/cmdline`, or shell history. You can run the
installer straight from GitHub via stdin (the script self-bootstraps
to disk if `BASH_SOURCE[0]` is empty under `set -u`):

```bash
# 1. Stage secrets (once per host)
sudo install -m 0600 /dev/null /etc/hostaffin/install.env
sudo vi /etc/hostaffin/install.env
#   HOSTAFFIN_MODE=local
#   HOSTAFFIN_GITHUB_TOKEN=ghp_...

# 2. Pipe the installer straight from GitHub
sudo bash -c '
  curl -fsSL --proto =https \
    https://raw.githubusercontent.com/TheRabbiRifat/sGTM-Panel/main/infra/scripts/installer.sh \
    | env $(grep -h "^HOSTAFFIN_" /etc/hostaffin/install.env | xargs) bash -s -- install --non-interactive
'
```

For maximum safety, pin the installer to a known SHA-256 with
`--sha256 <hex>` (optional; the installer still aborts on download
error even without a pin).

See the [top-level README](../README.md#production-install--yum-family-distros)
for the full set of installer flags, env-vars, and the list of what
the installer does step-by-step.