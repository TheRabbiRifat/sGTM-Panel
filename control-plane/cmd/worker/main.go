package main

import (
	"context"
	"encoding/json"
	"os"
	"os/signal"
	"syscall"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/rs/zerolog"

	"github.com/hostaffin/sgtm/control-plane/internal/config"
	"github.com/hostaffin/sgtm/control-plane/internal/db"
	"github.com/hostaffin/sgtm/control-plane/internal/domain"
	"github.com/hostaffin/sgtm/control-plane/internal/observability"
	redisx "github.com/hostaffin/sgtm/control-plane/internal/redis"
	"github.com/hostaffin/sgtm/control-plane/internal/repos"
)

func main() {
	cfg := config.Load()
	logger := observability.NewLogger(cfg.LogLevel)
	logger.Info().Msg("starting control-plane worker")

	rdb, err := redisx.New(cfg.RedisURL)
	if err != nil {
		logger.Fatal().Err(err).Msg("redis")
	}
	defer rdb.Close()

	pg, err := db.NewPostgres(cfg.DatabaseURL, 5, 2)
	if err != nil {
		logger.Fatal().Err(err).Msg("postgres")
	}
	defer pg.Close()

	srv := asynq.NewServer(
		asynq.RedisClientOpt{
			Addr:     rdb.Client().Options().Addr,
			Password: rdb.Client().Options().Password,
			DB:       rdb.Client().Options().DB,
		},
		asynq.Config{
			Concurrency: 10,
			Queues: map[string]int{
				"critical": 6,
				"default":  3,
				"low":      1,
			},
			ErrorHandler: asynq.ErrorHandlerFunc(func(ctx context.Context, t *asynq.Task, err error) {
				logger.Error().Str("task", t.Type()).Err(err).Msg("task failed")
			}),
		},
	)
	mux := asynq.NewServeMux()

	planRepo := repos.NewPlanRepo(pg.DB)
	svcRepo := repos.NewServiceRepo(pg.DB)
	registerHandlers(mux, logger, planRepo, svcRepo)

	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
		<-sigCh
		logger.Info().Msg("worker shutting down")
		cancel()
		srv.Shutdown()
	}()

	if err := srv.Start(mux); err != nil {
		logger.Fatal().Err(err).Msg("asynq start")
	}
}

func registerHandlers(mux *asynq.ServeMux, log zerolog.Logger,
	planRepo *repos.PlanRepo, svcRepo *repos.ServiceRepo,
) {
	mux.HandleFunc("service:provision", func(ctx context.Context, t *asynq.Task) error {
		var p struct {
			ServiceID string `json:"service_id"`
		}
		_ = json.Unmarshal(t.Payload(), &p)
		log.Info().Str("service_id", p.ServiceID).Msg("provisioning service")
		id, err := uuid.Parse(p.ServiceID)
		if err != nil {
			return err
		}
		return svcRepo.UpdateStatus(ctx, id, domain.ServiceActive, nil)
	})

	mux.HandleFunc("service:restart", func(ctx context.Context, t *asynq.Task) error {
		var p struct {
			ServiceID string `json:"service_id"`
		}
		_ = json.Unmarshal(t.Payload(), &p)
		log.Info().Str("service_id", p.ServiceID).Msg("restarting service")
		return nil
	})

	mux.HandleFunc("service:upgrade", func(ctx context.Context, t *asynq.Task) error {
		var p struct {
			ServiceID string `json:"service_id"`
			PlanSlug  string `json:"plan_slug"`
		}
		_ = json.Unmarshal(t.Payload(), &p)
		log.Info().Str("service_id", p.ServiceID).Str("plan", p.PlanSlug).Msg("upgrading")
		return nil
	})

	mux.HandleFunc("service:container", func(ctx context.Context, t *asynq.Task) error {
		var p struct {
			ServiceID string `json:"service_id"`
			Action    string `json:"action"`
			NodeID    string `json:"node_id,omitempty"`
		}
		_ = json.Unmarshal(t.Payload(), &p)
		log.Info().Str("service_id", p.ServiceID).Str("action", p.Action).Msg("container op")
		return nil
	})

	mux.HandleFunc("domain:verify", func(ctx context.Context, t *asynq.Task) error {
		log.Info().Msg("domain verify")
		return nil
	})

	mux.HandleFunc("ssl:check", func(ctx context.Context, t *asynq.Task) error {
		log.Info().Msg("ssl check")
		return nil
	})

	mux.HandleFunc("quota:scan", func(ctx context.Context, t *asynq.Task) error {
		log.Info().Msg("quota scan")
		return nil
	})

	mux.HandleFunc("usage:rollup", func(ctx context.Context, t *asynq.Task) error {
		log.Info().Msg("usage rollup")
		return nil
	})
}