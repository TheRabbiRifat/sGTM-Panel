package handlers

import (
	"errors"

	"github.com/gofiber/fiber/v2"
	"github.com/rs/zerolog"

	"github.com/hostaffin/sgtm/control-plane/internal/auth"
	"github.com/hostaffin/sgtm/control-plane/internal/config"
	"github.com/hostaffin/sgtm/control-plane/internal/db"
	redisx "github.com/hostaffin/sgtm/control-plane/internal/redis"
	"github.com/hostaffin/sgtm/control-plane/internal/queue"
)

// Deps bundles dependencies for HTTP handlers.
type Deps struct {
	DB    *db.Postgres
	Redis *redisx.Redis
	Queue *queue.Asynq
	JWT   *auth.JWT
	Log   zerolog.Logger
	Cfg   *config.Config
}

// ErrorHandler converts errors to JSON.
func ErrorHandler(log zerolog.Logger) fiber.ErrorHandler {
	return func(c *fiber.Ctx, err error) error {
		code := fiber.StatusInternalServerError
		msg := "internal error"
		var fe *fiber.Error
		if errors.As(err, &fe) {
			code = fe.Code
			msg = fe.Message
		}
		if code >= 500 {
			log.Error().Err(err).Str("path", c.Path()).Msg("handler error")
		}
		return c.Status(code).JSON(fiber.Map{
			"error": fiber.Map{
				"code":       httpErrCode(code),
				"message":    msg,
				"request_id": c.Locals("requestid"),
			},
		})
	}
}

func httpErrCode(c int) string {
	switch c {
	case 400:
		return "bad_request"
	case 401:
		return "unauthorized"
	case 403:
		return "forbidden"
	case 404:
		return "not_found"
	case 409:
		return "conflict"
	case 422:
		return "unprocessable"
	case 429:
		return "rate_limited"
	default:
		return "internal"
	}
}

// MountAPI wires up all v1 routes.
func MountAPI(app *fiber.App, d *Deps) {
	v1 := app.Group("/api", auth.Middleware(d.JWT))

	// Auth (login is unauthenticated; refresh too)
	authH := NewAuthHandler(d)
	app.Post("/api/auth/login", authH.Login)
	app.Post("/api/auth/refresh", authH.Refresh)

	// Services
	svcH := NewServiceHandler(d)
	v1.Get("/services", svcH.List)
	v1.Get("/services/:id", svcH.Get)
	v1.Get("/services/:id/usage", svcH.Usage)
	v1.Get("/services/:id/metrics", svcH.Metrics)
	v1.Post("/services/:id/restart", svcH.Restart)
	v1.Post("/services/:id/suspend", svcH.Suspend)
	v1.Post("/services/:id/unsuspend", svcH.Unsuspend)
	v1.Post("/services/:id/upgrade", svcH.Upgrade)
	v1.Post("/services/:id/move", svcH.Move)
	v1.Delete("/services/:id", svcH.Terminate)
	v1.Post("/services", auth.RequireRoles("super_admin", "admin"), svcH.Create)

	// Domains
	domH := NewDomainHandler(d)
	v1.Get("/services/:id/domains", domH.List)
	v1.Post("/services/:id/domains", domH.Create)
	v1.Post("/domains/:id/verify", domH.Verify)
	v1.Delete("/domains/:id", domH.Delete)

	// Loaders
	ldH := NewLoaderHandler(d)
	v1.Get("/services/:id/loaders", ldH.List)
	v1.Post("/services/:id/loaders", auth.RequireRoles("super_admin", "admin"), ldH.Create)
	v1.Get("/loaders/:loader_id", ldH.Get)
	v1.Put("/loaders/:loader_id/config", ldH.UpdateConfig)
	v1.Post("/loaders/:loader_id/regenerate", auth.RequireRoles("super_admin", "admin"), ldH.Regenerate)
	v1.Post("/loaders/:loader_id/disable", ldH.Disable)
	v1.Post("/loaders/:loader_id/enable", ldH.Enable)
	v1.Get("/loaders/:loader_id/analytics", ldH.Analytics)

	// Cookie Extensions
	ceH := NewCookieExtHandler(d)
	v1.Get("/services/:id/cookie-extensions", ceH.List)
	v1.Post("/services/:id/cookie-extensions", ceH.Create)
	v1.Put("/cookie-extensions/:id", ceH.Update)
	v1.Delete("/cookie-extensions/:id", ceH.Delete)
	v1.Post("/cookie-extensions/:id/test", ceH.Test)
	v1.Get("/cookie-extensions/:id/analytics", ceH.Analytics)
	v1.Get("/services/:id/cookie-extension-logs", ceH.Logs)

	// Plans / Nodes / Users / Audit
	planH := NewPlanHandler(d)
	v1.Get("/plans", planH.List)
	v1.Post("/plans", auth.RequireRoles("super_admin"), planH.Create)
	v1.Put("/plans/:id", auth.RequireRoles("super_admin"), planH.Update)

	nodeH := NewNodeHandler(d)
	v1.Get("/nodes", nodeH.List)
	v1.Post("/nodes", auth.RequireRoles("super_admin"), nodeH.Create)
	v1.Post("/nodes/:id/drain", auth.RequireRoles("super_admin", "admin"), nodeH.Drain)
	v1.Post("/nodes/:id/maintenance", auth.RequireRoles("super_admin", "admin"), nodeH.Maintenance)
	v1.Post("/nodes/:id/enable", auth.RequireRoles("super_admin", "admin"), nodeH.Enable)

	userH := NewUserHandler(d)
	v1.Get("/users", userH.List)
	v1.Post("/users", auth.RequireRoles("super_admin"), userH.Create)
	v1.Put("/users/:id", auth.RequireRoles("super_admin"), userH.Update)

	auditH := NewAuditHandler(d)
	v1.Get("/audit-logs", auditH.List)
}

// MountWebhooks wires up webhook endpoints (HMAC-signed, unauthenticated via JWT).
func MountWebhooks(app *fiber.App, _ *db.Postgres, _ *redisx.Redis, _ zerolog.Logger) {
	app.Post("/webhooks/whmcs", func(c *fiber.Ctx) error {
		// TODO: validate HMAC + signature, then enqueue events.
		return c.JSON(fiber.Map{"ok": true, "event": "received"})
	})
	app.Post("/webhooks/nodes/:id/metrics", func(c *fiber.Ctx) error {
		// TODO: validate node API key, ingest to ClickHouse.
		return c.JSON(fiber.Map{"ok": true})
	})
	app.Post("/webhooks/nodes/:id/deploy-result", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{"ok": true})
	})
	app.Post("/internal/ingest/metrics", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{"ok": true})
	})
}