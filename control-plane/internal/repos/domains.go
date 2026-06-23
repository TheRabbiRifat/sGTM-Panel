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

type DomainRepo struct{ db *sqlx.DB }

func NewDomainRepo(db *sqlx.DB) *DomainRepo { return &DomainRepo{db: db} }

func (r *DomainRepo) Create(ctx context.Context, d *domain.Domain) error {
	if d.ID == uuid.Nil {
		d.ID = uuid.New()
	}
	if d.CreatedAt.IsZero() {
		d.CreatedAt = time.Now()
	}
	if d.VerificationToken == "" {
		d.VerificationToken = randomHex(32)
	}
	_, err := r.db.NamedExecContext(ctx, `INSERT INTO domains
		(id,service_id,domain,is_primary,ssl_status,verified,verification_token,created_at)
		VALUES (:id,:service_id,:domain,:is_primary,:ssl_status,:verified,:verification_token,:created_at)`, d)
	return err
}

func (r *DomainRepo) GetByID(ctx context.Context, id uuid.UUID) (*domain.Domain, error) {
	var d domain.Domain
	err := r.db.GetContext(ctx, &d, `SELECT * FROM domains WHERE id=$1`, id)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return &d, err
}

func (r *DomainRepo) GetByDomain(ctx context.Context, name string) (*domain.Domain, error) {
	var d domain.Domain
	err := r.db.GetContext(ctx, &d, `SELECT * FROM domains WHERE domain=$1`, name)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return &d, err
}

func (r *DomainRepo) ListByService(ctx context.Context, serviceID uuid.UUID) ([]domain.Domain, error) {
	var out []domain.Domain
	err := r.db.SelectContext(ctx, &out,
		`SELECT * FROM domains WHERE service_id=$1 ORDER BY is_primary DESC, created_at DESC`, serviceID)
	return out, err
}

func (r *DomainRepo) MarkVerified(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `UPDATE domains SET verified=TRUE, last_checked_at=now() WHERE id=$1`, id)
	return err
}

func (r *DomainRepo) UpdateSSL(ctx context.Context, id uuid.UUID, status string) error {
	_, err := r.db.ExecContext(ctx, `UPDATE domains SET ssl_status=$2, last_checked_at=now() WHERE id=$1`, id, status)
	return err
}

func (r *DomainRepo) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `DELETE FROM domains WHERE id=$1`, id)
	return err
}