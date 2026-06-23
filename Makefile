# ───────────────────────────────────────────────
# Hostaffin sGTM Platform — root Makefile
# ───────────────────────────────────────────────

SHELL := /bin/bash

# Service config
COMPOSE ?= docker compose
GO ?= go
NODE ?= pnpm

# ── Repo-wide ──────────────────────────────
.PHONY: help
help:
	@echo "Hostaffin sGTM Platform — make targets"
	@echo ""
	@echo "Local dev:"
	@echo "  make up          Start docker compose (postgres, redis, clickhouse, traefik)"
	@echo "  make down        Stop docker compose"
	@echo "  make logs        Tail docker compose logs"
	@echo "  make migrate     Run database migrations"
	@echo "  make seed        Seed initial admin + plans"
	@echo ""
	@echo "Control plane:"
	@echo "  make run-api     Run the API server"
	@echo "  make run-worker  Run the background worker"
	@echo "  make test        Run Go tests"
	@echo "  make lint        Run linters"
	@echo ""
	@echo "Admin panel:"
	@echo "  make run-admin   Run Next.js dev server"
	@echo ""
	@echo "Misc:"
	@echo "  make keys        Generate JWT keypair"
	@echo "  make fmt         Format all code"

.PHONY: up down logs
up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f --tail=100

.PHONY: migrate seed
migrate:
	cd control-plane && $(GO) run ./cmd/migrate up

seed:
	cd control-plane && $(GO) run ./cmd/seed

.PHONY: run-api run-worker
run-api:
	cd control-plane && $(GO) run ./cmd/api

run-worker:
	cd control-plane && $(GO) run ./cmd/worker

.PHONY: test lint fmt
test:
	cd control-plane && $(GO) test ./...
	cd node-agent && $(GO) test ./...

lint:
	cd control-plane && golangci-lint run ./...
	cd node-agent && golangci-lint run ./...

fmt:
	cd control-plane && $(GO) fmt ./...
	cd node-agent && $(GO) fmt ./...
	cd admin-panel && $(NODE) format

.PHONY: run-admin
run-admin:
	cd admin-panel && $(NODE) dev

.PHONY: keys
keys:
	@mkdir -p control-plane/keys
	@openssl genpkey -algorithm RSA -out control-plane/keys/private.pem -pkeyopt rsa_keygen_bits:2048 2>/dev/null
	@openssl rsa -in control-plane/keys/private.pem -pubout -out control-plane/keys/public.pem 2>/dev/null
	@echo "Generated control-plane/keys/{private,public}.pem"