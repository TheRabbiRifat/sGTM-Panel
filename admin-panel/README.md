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
- `/services/move` — bulk-move services between master nodes (admin only)
- `/nodes`
- `/plans`
- `/users`
- `/audit-logs`
- `/settings`

## Move Service (admin only)

Like WHM's **Transfer Account** tool — relocate an sGTM container from one
master node to another. Useful for rebalancing load, draining a node for
maintenance, or recovering from a failed node. Gated to admin role on
the control plane.

### Single-service move

Open `/services/:id` and click **Move to another node**:

1. The dialog shows the service's current node (with CPU / RAM / container count).
2. Pick an online master node from the candidate list.
3. (Recommended) Click **Drain** on the destination node first so no new
   containers land on it during the transfer.
4. Type the service's edge hostname to confirm — typo-proof safety check
   borrowed from WHM.
5. The container is re-pulled on the destination, redeployed with the same
   plan / loader / cookie / domain settings, and `services.node_id` is
   updated. Traefik re-discovers the route via Docker labels (no DNS change).

Tracking on the service pauses for ~30–90 s during the move.

### Bulk move

Open `/services/move`:

1. Pick a destination master node.
2. Review the table of every active service currently on a *different* node —
   these are the ones that will be moved.
3. Tick the confirmation box and click **Move N services → hostname**.
4. The page issues one `POST /api/services/:id/move` per affected service in
   parallel and reports per-service success / failure in a collapsible details
   block.

### Safety pattern

For zero-impact transfers on a busy platform:

1. **Drain** the destination node (`POST /api/nodes/:id/drain`) — stops new
   containers landing on it.
2. **Move** the service(s) — control-plane worker re-deploys on the
   destination.
3. Optional: re-enable the node later by toggling its status back to
   `online` via the Nodes page.

### API

| Verb   | Path                          | Purpose                                    |
| ------ | ----------------------------- | ------------------------------------------ |
| `POST` | `/api/services/:id/move`      | Move a single service to another master    |
| `POST` | `/api/nodes/:id/drain`        | Stop new containers landing on a master    |

## Build

```bash
npm run build
npm start
```

The production build uses `output: 'standalone'` for a small Docker image.