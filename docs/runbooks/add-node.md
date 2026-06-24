# Runbook: Add a new master node

## When

Onboarding a new physical host to the swarm. Every node in the cluster is a
**master node** — there is no separate "edge" or "slave" role. All nodes can
serve traffic, run Traefik, and host customer containers.

## Steps

1. **Install base packages**

   ```bash
   apt-get update && apt-get install -y curl ca-certificates
   ```

2. **Install Docker**

   ```bash
   curl -fsSL https://get.docker.com | sh
   systemctl enable --now docker
   ```

3. **Join the Swarm**

   ```bash
   docker swarm join --token <manager-token> <manager-ip>:2377
   ```

4. **Label the node** (every node is a master)

   ```bash
   docker node update --label-add hostaffin_role=master <node-id>
   ```

5. **Create the overlay network** (only once per cluster, idempotent)

   ```bash
   docker network create --driver overlay --attachable hostaffin_edge
   ```

6. **Install node-agent**

   ```bash
   apt-get install -y rsync
   rsync -av infra/ root@<node-ip>:/root/hostaffin/
   ssh root@<node-ip> /root/hostaffin/scripts/bootstrap-node.sh
   ```

7. **Verify**

   ```bash
   ssh root@<node-ip> systemctl status hostaffin-node-agent
   ```

   On the control plane admin panel → Nodes → confirm new node is `online`
   and its `role` is `master`.

## Rollback

```bash
docker node update --availability drain <node-id>
docker node rm <node-id>
```