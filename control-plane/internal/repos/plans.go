package repos

import (
	"context"
	"database/sql"
	"errors"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"

	"github.com/hostaffin/sgtm/control-plane/internal/domain"
)

type PlanRepo struct{ db *sqlx.DB }

func NewPlanRepo(db *sqlx.DB) *PlanRepo { return &PlanRepo{db: db} }

func (r *PlanRepo) GetByID(ctx context.Context, id uuid.UUID) (*domain.Plan, error) {
	var p domain.Plan
	err := r.db.GetContext(ctx, &p, `SELECT * FROM plans WHERE id=$1`, id)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return &p, err
}

func (r *PlanRepo) GetBySlug(ctx context.Context, slug string) (*domain.Plan, error) {
	var p domain.Plan
	err := r.db.GetContext(ctx, &p, `SELECT * FROM plans WHERE slug=$1`, slug)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return &p, err
}

func (r *PlanRepo) GetByWhmcsProductID(ctx context.Context, pid int) (*domain.Plan, error) {
	var p domain.Plan
	err := r.db.GetContext(ctx, &p, `SELECT * FROM plans WHERE whmcs_product_id=$1`, pid)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return &p, err
}

func (r *PlanRepo) List(ctx context.Context, activeOnly bool) ([]domain.Plan, error) {
	q := `SELECT * FROM plans`
	if activeOnly {
		q += ` WHERE is_active=TRUE`
	}
	q += ` ORDER BY price_cents ASC`
	var out []domain.Plan
	err := r.db.SelectContext(ctx, &out, q)
	return out, err
}

func (r *PlanRepo) Upsert(ctx context.Context, p *domain.Plan) error {
	if p.ID == uuid.Nil {
		p.ID = uuid.New()
	}
	_, err := r.db.NamedExecContext(ctx, `INSERT INTO plans
		(id,whmcs_product_id,name,slug,cpu_limit,ram_limit_mb,request_limit,
		 bandwidth_limit_gb,container_replicas,price_cents,currency,is_active)
		VALUES (:id,:whmcs_product_id,:name,:slug,:cpu_limit,:ram_limit_mb,:request_limit,
		        :bandwidth_limit_gb,:container_replicas,:price_cents,:currency,:is_active)
		ON CONFLICT (slug) DO UPDATE SET
			name=EXCLUDED.name,
			cpu_limit=EXCLUDED.cpu_limit,
			ram_limit_mb=EXCLUDED.ram_limit_mb,
			request_limit=EXCLUDED.request_limit,
			bandwidth_limit_gb=EXCLUDED.bandwidth_limit_gb,
			price_cents=EXCLUDED.price_cents,
			is_active=EXCLUDED.is_active`, p)
	return err
}