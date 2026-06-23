# Node Agent

Runs on every Docker host (manager or worker) that hosts sGTM containers.

## Responsibilities

- Receives deploy/delete/restart commands from the Control Plane.
- Operates the local Docker daemon (Swarm-aware).
- Periodically posts heartbeats and per-container metrics.

## Run locally

```bash
NODE_ID=edge-local-01 \
NODE_API_KEY=dev-node-key \
CONTROL_PLANE_URL=http://localhost:8080 \
go run ./cmd/agent
```

## Layout

```
node-agent/
├── cmd/agent/main.go
└── internal/
    ├── commands/      # deploy / restart / delete
    ├── config/        # env-based config
    ├── heartbeat/     # liveness pings
    └── metrics/       # docker stats + scrape
```