# Runbook: Failover

## When

A node goes offline or a manager is unreachable.

## Steps

### 1. Confirm

```bash
docker node ls
# Look for *Status* column and *Availability*
```

### 2. Mark active services for re-scheduling

```bash
./control-plane migrate
./control-plane api  # exposes admin CLI (v2)
```

For v1, manually:

```bash
# For each service whose node_id == failed_node:
psql $DATABASE_URL -c "
  UPDATE services SET status='pending', updated_at=now()
  WHERE node_id='<failed-uuid>';
"
# Asynq worker will re-pick a node and redeploy.
```

### 3. Replace manager (if manager node failed)

```bash
# On a healthy manager:
docker node promote <worker-id>
docker node demote  <failed-id>
```

### 4. Update DNS / edge hostnames (if applicable)

If a customer's `edge_hostname` is locked to the failed node:

- The control plane picks a new node and redeploys the container.
- Traefik re-discovers via Docker labels.
- DNS for `*.edge.hostaffin.com` is wildcard CNAMEd to all master nodes; no customer-side change needed.

### 5. Notify affected customers

Webhook event `node.offline` is dispatched automatically. Manual outreach
via the email template `node_outage` if the outage exceeds 30 minutes.

## Post-mortem checklist

- [ ] Timeline of events
- [ ] Root cause
- [ ] Customer impact (# of services, downtime per service)
- [ ] Action items
- [ ] Update runbook