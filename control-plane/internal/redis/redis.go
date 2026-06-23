package redisx

import (
	"context"
	"fmt"

	"github.com/redis/go-redis/v9"
)

// Redis wraps a *redis.Client.
type Redis struct {
	*redis.Client
}

// New opens a Redis connection.
func New(url string) (*Redis, error) {
	opt, err := redis.ParseURL(url)
	if err != nil {
		return nil, fmt.Errorf("parse redis url: %w", err)
	}
	c := redis.NewClient(opt)
	if err := c.Ping(context.Background()).Err(); err != nil {
		return nil, fmt.Errorf("ping redis: %w", err)
	}
	return &Redis{Client: c}, nil
}

// Ping checks the connection.
func (r *Redis) Ping(ctx context.Context) error {
	return r.Client.Ping(ctx).Err()
}