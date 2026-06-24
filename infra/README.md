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
    ├── install-interactive.sh     # ASCII-UI wizard (timezone, DNS, mode, …)
    ├── install-almalinux9.sh      # YUM-family installer (the canonical one)
    ├── uninstall-almalinux9.sh    # YUM-family uninstaller
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

Both `install-interactive.sh` and `install-almalinux9.sh` accept **any
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

# Direct, non-interactive
sudo ./infra/scripts/install-almalinux9.sh \
  --mode local \
  --control-plane-url http://localhost:8080 \
  --non-interactive
```