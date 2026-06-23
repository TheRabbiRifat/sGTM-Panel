# Control Plane (Go + Fiber)

The single source of truth for the Hostaffin sGTM platform.

## Local dev

```bash
go run ./cmd/migrate up
go run ./cmd/seed
go run ./cmd/api
```

In another terminal:

```bash
go run ./cmd/worker
```

## Endpoints

See `internal/handlers/handlers.go` for the full route table.

Highlights:

- `POST /api/auth/login` — admin login
- `POST /api/services` — provision
- `GET  /api/services/:id` — fetch
- `POST /api/services/:id/{restart,suspend,unsuspend,upgrade,move}`
- `POST /api/services/:id/domains` and `POST /api/domains/:id/verify`
- `GET/POST /api/services/:id/loaders`, `POST /api/loaders/:id/regenerate`
- `GET/POST /api/services/:id/cookie-extensions`, `POST /api/cookie-extensions/:id/test`
- `GET /loader.js?id=...` — public, served by Traefik in prod
- `GET /loader.js/run?id=...` — runtime hit counter
- `POST/GET /cookie/extend/:name` — public cookie extension endpoints

## Layout

```
control-plane/
├── cmd/
│   ├── api/        # HTTP server
│   ├── worker/     # Asynq background worker
│   ├── migrate/    # SQL migration runner
│   └── seed/       # Initial plans + super_admin
├── internal/
│   ├── auth/       # JWT + Argon2id password hashing
│   ├── config/     # viper-based config
│   ├── db/         # pgx + sqlx pool
│   ├── domain/     # model types
│   ├── handlers/   # Fiber HTTP handlers
│   ├── observability/  # zerolog + Fiber logger
│   ├── queue/      # Asynq client/server
│   ├── redis/      # go-redis wrapper
│   ├── repos/      # repositories
│   └── services/   # business logic
└── migrations/     # SQL migrations
```

## License

Proprietary — Hostaffin Ltd.