# WHMCS Module — Hostaffin sGTM

WHMCS-side integration for the Hostaffin sGTM Hosting Platform. Lets
customers self-serve almost every feature of their sGTM container from
the WHMCS client area — no admin tickets required.

## Files

```
whmcs-module/
└── modules/
    └── servers/
        └── hostaffin_sgtm/
            ├── hostaffin_sgtm.php        # Module entrypoint: lifecycle + action handlers
            ├── callback.php              # Webhook receiver (HMAC-signed)
            ├── lib/
            │   ├── ApiClient.php         # cURL wrapper for the Control Plane API
            │   └── Hooks.php             # Custom-field helpers + block-aware template engine
            └── templates/
                └── clientarea.tpl        # Server-rendered client area panel
```

## What the client can do from the WHMCS client area

| Feature                       | What they can do                                                                                         |
| ----------------------------- | -------------------------------------------------------------------------------------------------------- |
| **Service status + plan**     | View status, plan, container URL                                                                          |
| **Usage / request count**     | Monthly request count, loader hits, cookie-ext hits, bandwidth                                           |
| **Custom domain**             | Add a domain → receive CNAME / TXT instructions → re-verify DNS → ACME cert issued                      |
| **Custom loader**             | Pick JS alias (`gtm.js`, `trk-ss.js`, `gtag.js`, `analytics.js`, `fbevents.js`, `pixel.js`, `loader.js`, `trk.js`, `custom`), set trigger (immediate / delay / consent cookie / on element), map `_fbp` / `_fbc` cookies, honor DNT, pause / resume, rotate |
| **Cookie lifetime extension** | Add extension (cookie name + vendor URL + lifetime ≤ 395 days), pause / resume, delete                   |
| **Restart container**         | One-click restart                                                                                         |

## Installation

1. Copy `modules/servers/hostaffin_sgtm/` into your WHMCS install under
   `modules/servers/`.
2. WHMCS Admin → Setup → Products → Products/Services → Create New Product:
   - Module: **Hostaffin sGTM Hosting**
3. Configure server credentials at Setup → Products → Servers:
   - Hostname: `control-plane.hostaffin.com`
   - Password: `<your API key>`
4. Set the webhook URL in Automation → Webhooks:
   `https://<your-whmcs>/modules/servers/hostaffin_sgtm/callback.php`
5. Custom fields are auto-created on first run:
   - `service_id` (text)
   - `edge_hostname` (text)
   - `plan_slug` (text)

## Environment variables

| Var                        | Purpose                                       |
| -------------------------- | --------------------------------------------- |
| `HOSTAFFIN_API_URL`        | Default `http://localhost:8080` if unset      |
| `HOSTAFFIN_API_KEY`        | Used if server password is empty              |
| `HOSTAFFIN_WEBHOOK_SECRET` | HMAC secret for `callback.php`                |

## Control-plane endpoints used

| Verb     | Path                                          | Purpose                                       |
| -------- | --------------------------------------------- | --------------------------------------------- |
| `GET`    | `/api/services/:id`                           | Service detail + status                       |
| `GET`    | `/api/services/:id/usage`                     | Monthly request count, hits, bandwidth        |
| `GET`    | `/api/services/:id/loaders`                   | List loaders                                  |
| `POST`   | `/api/services/:id/loaders`                   | Create loader (alias + FBP/FBC + trigger)     |
| `GET`    | `/api/loaders/:loader_id`                     | Loader + config + rendered snippet + SRI      |
| `PUT`    | `/api/loaders/:loader_id/config`              | Update loader config                          |
| `POST`   | `/api/loaders/:loader_id/regenerate`          | Rotate loader id                              |
| `POST`   | `/api/loaders/:loader_id/enable`              | Resume loader                                 |
| `POST`   | `/api/loaders/:loader_id/disable`             | Pause loader                                  |
| `GET`    | `/api/services/:id/cookie-extensions`         | List extensions                               |
| `POST`   | `/api/services/:id/cookie-extensions`         | Add extension                                 |
| `PUT`    | `/api/cookie-extensions/:id`                  | Update / toggle extension                     |
| `DELETE` | `/api/cookie-extensions/:id`                  | Remove extension                              |
| `GET`    | `/api/services/:id/domains`                   | List custom domains                           |
| `POST`   | `/api/services/:id/domains`                   | Add custom domain                             |
| `POST`   | `/api/domains/:id/verify`                     | Re-check DNS                                  |
| `DELETE` | `/api/domains/:id`                            | Remove custom domain                          |
| `POST`   | `/api/services/:id/restart`                   | Restart container                             |

## Webhook events

The Control Plane POSTs to `callback.php` with header
`X-Hostaffin-Signature: <hex-hmac-sha256(secret, body)>` for these events:

- `service.provisioned`
- `service.failed`
- `service.suspended`
- `service.unsuspended`
- `service.terminated`
- `domain.verified`
- `ssl.issued`
- `ssl.failed`
- `quota.exceeded`
- `loader.regenerated`

## CSRF protection

Every state-changing form (`addDomain`, `verifyDomain`, `createLoader`,
`regenerateLoader`, `toggleLoader`, `createCookie`, `toggleCookie`,
`restart`) is protected by the standard WHMCS CSRF token injected via
`{$token}` and verified in `Hooks::checkCsrf()`.

## Customization

- **Aliases**: edit `Hostaffin_Hooks::jsAliasOptions()` in `lib/Hooks.php`.
- **Default FBP/FBC names**: edit `_hostaffin_sgtm_loaderPayloadFromPost()`.
- **Vendor presets**: edit `Hostaffin_Hooks::cookieAliasPresets()`.
- **Template**: edit `templates/clientarea.tpl`. The block-aware
  renderer in `Hooks::renderString()` supports:
  - `{{var.path}}` and `{{.field}}` (child-item access inside `{{range}}`)
  - `{{if X}} … {{else}} … {{end}}` (nesting-safe)
  - `{{range items}} … {{else}} … {{end}}` (nesting-safe)
  - `{{X|default:Y}}`, `{{X|raw}}` (no HTML escape), `{{X|upper}}`, `{{X|lower}}`
  - `{{partial name}}` to include another template
