# API Reference

The Hostaffin sGTM Control Plane exposes a REST API under `/api/*`. Auth is JWT (RS256).

## Auth

```http
POST /api/auth/login
Content-Type: application/json

{"email":"admin@hostaffin.local","password":"..."}
```

Response:
```json
{
  "access_token": "eyJ...",
  "refresh_token": "eyJ...",
  "user_id": "...",
  "email": "...",
  "role": "super_admin"
}
```

Use `Authorization: Bearer <access_token>` on all subsequent calls.

## Services

```http
POST   /api/services                  # provision new service
GET    /api/services                  # list (filters: status, plan, node, search, whmcs_client_id)
GET    /api/services/:id              # fetch
DELETE /api/services/:id              # terminate
POST   /api/services/:id/restart
POST   /api/services/:id/suspend
POST   /api/services/:id/unsuspend
POST   /api/services/:id/upgrade      # body: {"plan_slug":"growth"}
POST   /api/services/:id/move         # body: {"node_id":"<uuid>"}
GET    /api/services/:id/usage        # this-month rollup + daily series
GET    /api/services/:id/metrics      # 5-min series from ClickHouse
```

## Domains

```http
POST   /api/services/:id/domains      # body: {"domain":"track.client.com"}
GET    /api/services/:id/domains
POST   /api/domains/:id/verify        # runs DNS check
DELETE /api/domains/:id
```

## Custom Loaders

```http
GET    /api/services/:id/loaders
POST   /api/services/:id/loaders      # body: {"mode":"live","trigger_type":"immediate"}
GET    /api/loaders/:loader_id        # returns loader + config + snippet + SRI hash
PUT    /api/loaders/:loader_id/config # body: {"trigger_type":"delay","trigger_value":"2000","respect_dnt":true}
POST   /api/loaders/:loader_id/regenerate
POST   /api/loaders/:loader_id/disable
GET    /api/loaders/:loader_id/analytics
```

## Cookie Extensions

```http
GET    /api/services/:id/cookie-extensions
POST   /api/services/:id/cookie-extensions
PUT    /api/cookie-extensions/:id
DELETE /api/cookie-extensions/:id
POST   /api/cookie-extensions/:id/test  # synthetic request, returns the Set-Cookie that WOULD be sent
GET    /api/cookie-extensions/:id/analytics
GET    /api/services/:id/cookie-extension-logs?limit=100
```

## Public endpoints (no auth, rate-limited)

```http
GET  /loader.js?id=<loader_id>           # returns the loader JS
GET  /loader.js/run?id=<loader_id>       # runtime hit counter
GET  /cookie/extend/:name                # read an extended cookie
POST /cookie/extend/:name                # set / extend an extended cookie
GET  /cookie/extend                      # list (debug)
```

## Admin

```http
GET/POST/PUT /api/plans
GET/POST     /api/nodes
POST         /api/nodes/:id/{drain,maintenance,enable}
GET/POST/PUT /api/users
GET          /api/audit-logs
```

## Webhooks (HMAC-signed)

```http
POST /webhooks/whmcs                      # from control plane to WHMCS
POST /webhooks/nodes/:id/metrics          # from node agent
POST /webhooks/nodes/:id/deploy-result    # from node agent
POST /internal/ingest/metrics             # from node agent
POST /internal/heartbeat                  # from node agent
```

## Error format

```json
{
  "error": {
    "code": "not_found",
    "message": "service not found",
    "request_id": "uuid"
  }
}
```