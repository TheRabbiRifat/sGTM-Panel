package queue

import (
	"context"
	"fmt"

	"github.com/hibiken/asynq"
	"github.com/redis/go-redis/v9"
	"github.com/rs/zerolog"
)

// Asynq is a thin wrapper around asynq.Client.
type Asynq struct {
	client *asynq.Client
	env    string
}

// NewAsynq creates the client.
func NewAsynq(rdb *redis.Client, env string) *Asynq {
	return &Asynq{
		client: asynq.NewClientFromRedis(rdb),
		env:    env,
	}
}

// Client returns the underlying asynq.Client.
func (a *Asynq) Client() *asynq.Client { return a.client }

// Enqueue queues a task. typeName is e.g. "service:provision".
func (a *Asynq) Enqueue(ctx context.Context, typeName string, payload []byte, opts ...asynq.Option) error {
	t := asynq.NewTask(typeName, payload)
	_, err := a.client.EnqueueContext(ctx, t, opts...)
	return err
}

// Handler is a function that processes a task.
type Handler func(ctx context.Context, t *asynq.Task) error

// Server wraps an asynq.Server with a mux.
type Server struct {
	srv    *asynq.Server
	mux    *asynq.ServeMux
	logger zerolog.Logger
}

// NewServer constructs a server with sane defaults.
func NewServer(rdb *redis.Client, env string, logger zerolog.Logger) *Server {
	srv := asynq.NewServer(
		asynq.RedisClientOpt{Addr: rdb.Options().Addr, Password: rdb.Options().Password, DB: rdb.Options().DB},
		asynq.Config{
			Concurrency: 10,
			Queues: map[string]int{
				"critical": 6,
				"default":  3,
				"low":      1,
			},
		},
	)
	mux := asynq.NewServeMux()
	s := &Server{srv: srv, mux: mux, logger: logger}
	srv.Run(mux) // not started; we call Start/Stop
	return s
}

// Register binds a task type to a handler.
func (s *Server) Register(typeName string, h Handler) {
	s.mux.HandleFunc(typeName, func(ctx context.Context, t *asynq.Task) error {
		if err := h(ctx, t); err != nil {
			s.logger.Error().Str("task", typeName).Err(err).Msg("task failed")
			return err
		}
		return nil
	})
}

// Start begins processing. Blocks until Stop is called.
func (s *Server) Start() error {
	if err := s.srv.Start(s.mux); err != nil {
		return fmt.Errorf("asynq start: %w", err)
	}
	return nil
}

// Stop gracefully shuts down the server.
func (s *Server) Stop() {
	s.srv.Shutdown()
}