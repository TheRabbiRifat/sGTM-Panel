# Traefik

Reverse proxy, TLS terminator, and Docker service discovery for the Hostaffin sGTM Platform.

## Files

- `traefik.yml` — static configuration (entrypoints, providers, ACME).
- `docker-compose.yml` — reference stack to run Traefik on a master node.
- `sample-sgtm-stack.yml` — example of the labels the Control Plane writes
  when provisioning a service. Shows how Traefik auto-discovers the sGTM
  container, the Custom Loader, and the Cookie Extension route.

## How routing works

1. Control Plane picks a master node and writes a stack with `Host(...)`, `PathPrefix(...)` labels.
2. Traefik (running with `providers.docker.swarmMode: true`) auto-discovers services.
3. ACME issues a Let's Encrypt cert on first request to the new hostname.
4. Custom Loader served at `/loader.js`; runtime hit at `/loader.js/run`.
5. Cookie Extension served at `/cookie/...` (prefix stripped by middleware).

## Bootstrapping a master node

Every node is a master node — there is no slave/non-edge role. Any node can
host Traefik and serve customer traffic.

```bash
docker swarm init --advertise-addr <node_ip>
docker node update --label-add hostaffin_role=master <node_id>
docker stack deploy -c docker-compose.yml traefik
```