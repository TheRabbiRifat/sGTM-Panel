package repos

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"

	"github.com/hostaffin/sgtm/control-plane/internal/domain"
)

type NodeRepo struct{ db *sqlx.DB }

func NewNodeRepo(db *sqlx.DB) *NodeRepo { return &NodeRepo{db: db} }

func (r *NodeRepo) GetByID(ctx context.Context, id uuid.UUID) (*domain.Node, error) {
	var n domain.Node
	err := r.db.GetContext(ctx, &n, `SELECT * FROM nodes WHERE id=$1`, id)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return &n, err
}

func (r *NodeRepo) GetByHostname(ctx context.Context, h string) (*domain.Node, error) {
	var n domain.Node
	err := r.db.GetContext(ctx, &n, `SELECT * FROM nodes WHERE hostname=$1`, h)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return &n, err
}

func (r *NodeRepo) List(ctx context.Context) ([]domain.Node, error) {
	var out []domain.Node
	err := r.db.SelectContext(ctx, &out, `SELECT * FROM nodes ORDER BY hostname`)
	return out, err
}

func (r *NodeRepo) ListOnline(ctx context.Context) ([]domain.Node, error) {
	var out []domain.Node
	err := r.db.SelectContext(ctx, &out,
		`SELECT * FROM nodes WHERE status='online' AND role='master' ORDER BY hostname`)
	return out, err
}

func (r *NodeRepo) Upsert(ctx context.Context, n *domain.Node) error {
	if n.ID == uuid.Nil {
		n.ID = uuid.New()
	}
	// Every node is a master node — there is no slave role. Force role='master'
	// on insert to enforce that invariant at the data layer.
	if n.Role == "" {
		n.Role = domain.NodeRoleMaster
	}
	_, err := r.db.NamedExecContext(ctx, `INSERT INTO nodes
		(id,hostname,region,status,total_cpu,total_ram_mb,role)
		VALUES (:id,:hostname,:region,:status,:total_cpu,:total_ram_mb,:role)
		ON CONFLICT (hostname) DO UPDATE SET
			region=EXCLUDED.region,
			status=EXCLUDED.status,
			total_cpu=EXCLUDED.total_cpu,
			total_ram_mb=EXCLUDED.total_ram_mb,
			role=EXCLUDED.role`, n)
	return err
}

func (r *NodeRepo) UpdateHeartbeat(ctx context.Context, id uuid.UUID, status domain.NodeStatus, usedCPU float64, usedRAM int) error {
	_, err := r.db.ExecContext(ctx, `UPDATE nodes
		SET last_heartbeat=now(), status=$2, used_cpu=$3, used_ram_mb=$4
		WHERE id=$1`, id, status, usedCPU, usedRAM)
	return err
}

func (r *NodeRepo) MarkStale(ctx context.Context, threshold time.Duration) ([]uuid.UUID, error) {
	rows, err := r.db.QueryxContext(ctx, `UPDATE nodes SET status='offline'
		WHERE status='online' AND (last_heartbeat IS NULL OR last_heartbeat < now() - $1::interval)
		RETURNING id`, threshold.String())
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []uuid.UUID
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, nil
}