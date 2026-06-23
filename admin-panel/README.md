# Hostaffin Admin Panel (Next.js 14 + Shadcn)

Internal UI for managing sGTM services, nodes, plans, and customers.

## Quick start

```bash
npm install
cp .env.local.example .env.local       # then edit NEXT_PUBLIC_CONTROL_PLANE_URL
npm run dev
```

Open <http://localhost:3000>. Default login: `admin@hostaffin.local` / `ChangeMe!123`
(seeded by `control-plane/cmd/seed`).

## Pages

- `/login`
- `/dashboard`
- `/services`, `/services/[id]` (tabs: Overview, Loaders, Cookies, Metrics)
- `/nodes`
- `/plans`
- `/users`
- `/audit-logs`
- `/settings`

## Build

```bash
npm run build
npm start
```

The production build uses `output: 'standalone'` for a small Docker image.