# WHMCS Module — Hostaffin sGTM

This is the WHMCS-side integration for the Hostaffin sGTM Hosting Platform.

## Files

```
whmcs-module/
└── modules/
    └── servers/
        └── hostaffin_sgtm/
            ├── hostaffin_sgtm.php        # Module entrypoint (CreateAccount, Suspend, etc.)
            ├── callback.php              # Webhook receiver (HMAC-signed)
            ├── lib/
            │   ├── ApiClient.php         # cURL wrapper for the Control Plane API
            │   └── Hooks.php             # Custom field helpers + tiny template renderer
            └── templates/
                └── clientarea.tpl        # Server-rendered client area panel
```

## Installation

1. Copy `modules/servers/hostaffin_sgtm/` into your WHMCS install under the
   same path (`modules/servers/`).
2. In WHMCS Admin → Setup → Products → Products/Services → Create New Product:
   - Module: **Hostaffin sGTM Hosting**
   - Module Settings:
     - **Plan**: `starter` / `growth` / `agency`
3. Configure server credentials:
   - Admin → Setup → Products → Servers:
     - Hostname: `control-plane.hostaffin.com` (or your URL)
     - Username: optional
     - Password: `<your API key>`
4. Set the webhook URL in WHMCS → Automation → Webhooks (or via Settings → API):
   - `https://<your-whmcs>/modules/servers/hostaffin_sgtm/callback.php`
5. Add custom fields (auto-created on first run if missing):
   - `service_id` (text)
   - `edge_hostname` (text)
   - `plan_slug` (text)

## Environment variables

| Var | Purpose |
|---|---|
| `HOSTAFFIN_API_URL` | Default `http://localhost:8080` if server hostname not set |
| `HOSTAFFIN_API_KEY` | Used if server password is empty |
| `HOSTAFFIN_WEBHOOK_SECRET` | HMAC secret for `callback.php` |

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