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