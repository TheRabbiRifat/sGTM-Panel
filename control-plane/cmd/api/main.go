package main

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/recover"
	"github.com/gofiber/fiber/v2/middleware/requestid"

	"github.com/hostaffin/sgtm/control-plane/internal/auth"
	"github.com/hostaffin/sgtm/control-plane/internal/config"
	"github.com/hostaffin/sgtm/control-plane/internal/db"
	"github.com/hostaffin/sgtm/control-plane/internal/handlers"
	"github.com/hostaffin/sgtm/control-plane/internal/observability"
	"github.com/hostaffin/sgtm/control-plane/internal/queue"
	redisx "github.com/hostaffin/sgtm/control-plane/internal/redis"
)

func main() {
	cfg := config.Load()
	logger := observability.NewLogger(cfg.LogLevel)
	logger.Info().Str("env", cfg.AppEnv).Msg("starting control-plane api")

	pg, err := db.NewPostgres(cfg.DatabaseURL, cfg.DBMaxOpen, cfg.DBMaxIdle)
	if err != nil {
		logger.Fatal().Err(err).Msg("postgres connect")
	}
	defer pg.Close()

	rdb, err := redisx.New(cfg.RedisURL)
	if err != nil {
		logger.Fatal().Err(err).Msg("redis connect")
	}
	defer rdb.Close()

	q := queue.NewAsynq(rdb.Client(), cfg.AppEnv)
	mux := queue.NewMux(q, logger)

	jwtMgr := auth.NewJWT(cfg.JWTPrivateKeyPEM, cfg.JWTPublicKeyPEM,
		cfg.JWTAccessTTL, cfg.JWTRefreshTTL)

	app := fiber.New(fiber.Config{
		DisableStartupMessage: true,
		ErrorHandler:          handlers.ErrorHandler(logger),
		BodyLimit:             1 * 1024 * 1024,
		ReadTimeout:           30 * time.Second,
		WriteTimeout:          30 * time.Second,
		AppName:               "hostaffin-sgtm-control-plane",
	})

	app.Use(recover.New())
	app.Use(requestid.New())
	app.Use(observability.FiberLogger(logger))
	app.Use(cors.New(cors.Config{
		AllowOrigins:     "*",
		AllowMethods:     "GET,POST,PUT,DELETE,OPTIONS",
		AllowHeaders:     "Origin,Content-Type,Authorization,X-Requested-With,X-Hostaffin-Signature",
		AllowCredentials: false,
	}))

	// Health
	app.Get("/healthz", func(c *fiber.Ctx) error {
		if err := pg.Ping(c.Context()); err != nil {
			return fiber.NewError(http.StatusServiceUnavailable, "db down")
		}
		if err := rdb.Ping(c.Context()); err != nil {
			return fiber.NewError(http.StatusServiceUnavailable, "redis down")
		}
		return c.JSON(fiber.Map{"status": "ok", "ts": time.Now().UTC()})
	})

	// Webhooks (public — HMAC-signed)
	handlers.MountWebhooks(app, pg, rdb, logger)

	// Public loader + cookie extension endpoints (rate-limited)
	handlers.MountPublic(app, pg, rdb, logger)

	// API v1 (auth required)
	handlers.MountAPI(app, &handlers.Deps{
		DB:    pg,
		Redis: rdb,
		Queue: q,
		JWT:   jwtMgr,
		Log:   logger,
		Cfg:   cfg,
	})

	// Async worker (in-process for single-binary ops; can be split via cmd/worker)
	go func() {
		if err := mux.Run(context.Background()); err != nil {
			logger.Error().Err(err).Msg("asynq worker stopped")
		}
	}()

	// Graceful shutdown
	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
		<-sigCh
		logger.Info().Msg("shutting down")
		_ = app.ShutdownWithTimeout(10 * time.Second)
	}()

	addr := fmt.Sprintf(":%d", cfg.HTTPPort)
	logger.Info().Str("addr", addr).Msg("api listening")
	if err := app.Listen(addr); err != nil && !errors.Is(err, http.ErrServerClosed) {
		logger.Fatal().Err(err).Msg("listen")
	}
}