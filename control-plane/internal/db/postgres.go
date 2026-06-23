package db

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/jmoiron/sqlx"
	_ "github.com/jackc/pgx/v5/stdlib" // pgx stdlib driver
)

// Postgres wraps a sqlx pool backed by pgx for the application.
type Postgres struct {
	*sqlx.DB
	pool *pgxpool.Pool
}

// NewPostgres opens a connection pool with the given DSN.
func NewPostgres(dsn string, maxOpen, maxIdle int) (*Postgres, error) {
	db, err := sqlx.Open("pgx", dsn)
	if err != nil {
		return nil, fmt.Errorf("open: %w", err)
	}
	db.SetMaxOpenConns(maxOpen)
	db.SetMaxIdleConns(maxIdle)
	db.SetConnMaxLifetime(30 * time.Minute)

	// also open a pgxpool for streaming (used by ingestor)
	pcfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("parse dsn: %w", err)
	}
	pcfg.MaxConns = int32(maxOpen)
	pool, err := pgxpool.NewWithConfig(context.Background(), pcfg)
	if err != nil {
		return nil, fmt.Errorf("pgxpool: %w", err)
	}

	pingCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := db.PingContext(pingCtx); err != nil {
		return nil, fmt.Errorf("ping: %w", err)
	}
	return &Postgres{DB: db, pool: pool}, nil
}

// Pool returns the underlying pgxpool for callers that need streaming/ingestion.
func (p *Postgres) Pool() *pgxpool.Pool { return p.pool }

// Exec is a thin wrapper for one-off statements.
func (p *Postgres) Exec(query string, args ...any) (sql.Result, error) {
	return p.DB.Exec(query, args...)
}

// QueryRow is a thin wrapper.
func (p *Postgres) QueryRow(query string, args ...any) *sql.Row {
	return p.DB.QueryRow(query, args...)
}

// Close releases both pools.
func (p *Postgres) Close() {
	if p.DB != nil {
		_ = p.DB.Close()
	}
	if p.pool != nil {
		p.pool.Close()
	}
}