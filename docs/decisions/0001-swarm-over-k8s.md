# ADR-0001: Docker Swarm over Kubernetes

**Status:** Accepted (2026-06-23)

## Context

The v1 platform needs to schedule one container per customer across a small
cluster of hosts. Two options were considered: Kubernetes and Docker Swarm.

## Decision

We chose **Docker Swarm** for v1.

## Consequences

### Positive

- Much simpler operations (no etcd, no kube-apiserver, no kubelet).
- Native Traefik integration via Docker labels — zero config files to manage.
- Faster onboarding for engineers familiar with `docker compose`.
- Smaller blast radius during failures (no cascading restarts).

### Negative

- Less mature ecosystem (no Helm, fewer operators, no advanced schedulers).
- Hard limit on cluster size (~1000 nodes, but we expect <50 in v1).
- Manual node-agent deployment (no DaemonSet equivalent).

## When to revisit

- Cluster grows past ~50 nodes
- Need for advanced scheduling (affinity, taints, topology spread)
- Need for fine-grained RBAC inside the cluster
- Customer demand for self-hosted / on-prem deployment where K8s is the standard

If/when we move to K8s, the node-agent abstraction should make it possible
to replace Swarm calls with K8s client calls without changing the Control Plane.