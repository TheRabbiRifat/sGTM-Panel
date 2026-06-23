package repos

import (
	"context"
	"encoding/json"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
)

type AuditRepo struct{ db *sqlx.DB }

func NewAuditRepo(db *sqlx.DB) *AuditRepo { return &AuditRepo{db: db} }

type AuditEntry struct {
	UserID    *uuid.UUID
	ActorType string
	Action    string
	Resource  string
	Metadata  map[string]any
	IP        string
}

func (r *AuditRepo) Log(ctx context.Context, e AuditEntry) error {
	meta, _ := json.Marshal(e.Metadata)
	_, err := r.db.ExecContext(ctx, `INSERT INTO audit_logs
		(user_id,actor_type,action,resource,metadata,ip,created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7)`,
		e.UserID, e.ActorType, e.Action, e.Resource, meta, nullIfEmpty(e.IP), time.Now())
	return err
}

func (r *AuditRepo) List(ctx context.Context, limit, offset int) ([]AuditRow, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	var out []AuditRow
	err := r.db.SelectContext(ctx, &out, `SELECT * FROM audit_logs ORDER BY created_at DESC LIMIT $1 OFFSET $2`, limit, offset)
	return out, err
}

type AuditRow struct {
	ID        int64     `db:"id" json:"id"`
	UserID    *uuid.UUID `db:"user_id" json:"user_id,omitempty"`
	ActorType string    `db:"actor_type" json:"actor_type"`
	Action    string    `db:"action" json:"action"`
	Resource  *string   `db:"resource" json:"resource,omitempty"`
	Metadata  []byte    `db:"metadata" json:"metadata"`
	IP        *string   `db:"ip" json:"ip,omitempty"`
	CreatedAt time.Time `db:"created_at" json:"created_at"`
}

func nullIfEmpty(s string) interface{} {
	if s == "" {
		return nil
	}
	return s
}