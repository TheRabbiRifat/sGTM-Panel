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

type LoaderRepo struct{ db *sqlx.DB }

func NewLoaderRepo(db *sqlx.DB) *LoaderRepo { return &LoaderRepo{db: db} }

func (r *LoaderRepo) Create(ctx context.Context, l *domain.Loader, cfg *domain.LoaderConfig) error {
	if l.ID == uuid.Nil {
		l.ID = uuid.New()
	}
	if l.LoaderID == "" {
		l.LoaderID = "lk_" + randomHex(8)
	}
	if l.CreatedAt.IsZero() {
		l.CreatedAt = time.Now()
	}
	tx, err := r.db.BeginTxx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	if _, err := tx.NamedExecContext(ctx, `INSERT INTO loaders
		(id,service_id,loader_id,version,mode,is_active,hit_count,sri_hash,created_at)
		VALUES (:id,:service_id,:loader_id,:version,:mode,:is_active,:hit_count,:sri_hash,:created_at)`, l); err != nil {
		return err
	}
	cfg.LoaderID = l.LoaderID
	cfg.UpdatedAt = time.Now()
	if _, err := tx.NamedExecContext(ctx, `INSERT INTO loader_configs
		(loader_id,trigger_type,trigger_value,cookie_name,respect_dnt,allow_bots,
		 js_file_alias,fbp_cookie_name,fbc_cookie_name,honor_consent,vendor_mapping,updated_at)
		VALUES (:loader_id,:trigger_type,:trigger_value,:cookie_name,:respect_dnt,:allow_bots,
		 :js_file_alias,:fbp_cookie_name,:fbc_cookie_name,:honor_consent,:vendor_mapping,:updated_at)`, cfg); err != nil {
		return err
	}
	return tx.Commit()
}

func (r *LoaderRepo) GetByID(ctx context.Context, id string) (*domain.Loader, error) {
	var l domain.Loader
	err := r.db.GetContext(ctx, &l, `SELECT * FROM loaders WHERE loader_id=$1`, id)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return &l, err
}

func (r *LoaderRepo) GetConfig(ctx context.Context, id string) (*domain.LoaderConfig, error) {
	var c domain.LoaderConfig
	err := r.db.GetContext(ctx, &c, `SELECT * FROM loader_configs WHERE loader_id=$1`, id)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return &c, err
}

func (r *LoaderRepo) ListByService(ctx context.Context, serviceID uuid.UUID) ([]domain.Loader, error) {
	var out []domain.Loader
	err := r.db.SelectContext(ctx, &out,
		`SELECT * FROM loaders WHERE service_id=$1 ORDER BY created_at DESC`, serviceID)
	return out, err
}

func (r *LoaderRepo) UpdateConfig(ctx context.Context, c *domain.LoaderConfig) error {
	c.UpdatedAt = time.Now()
	_, err := r.db.NamedExecContext(ctx, `UPDATE loader_configs SET
		trigger_type=:trigger_type,
		trigger_value=:trigger_value,
		cookie_name=:cookie_name,
		respect_dnt=:respect_dnt,
		allow_bots=:allow_bots,
		js_file_alias=:js_file_alias,
		fbp_cookie_name=:fbp_cookie_name,
		fbc_cookie_name=:fbc_cookie_name,
		honor_consent=:honor_consent,
		vendor_mapping=:vendor_mapping,
		updated_at=:updated_at
		WHERE loader_id=:loader_id`, c)
	return err
}

func (r *LoaderRepo) Disable(ctx context.Context, id string) error {
	_, err := r.db.ExecContext(ctx, `UPDATE loaders SET is_active=FALSE WHERE loader_id=$1`, id)
	return err
}

func (r *LoaderRepo) Enable(ctx context.Context, id string) error {
	_, err := r.db.ExecContext(ctx, `UPDATE loaders SET is_active=TRUE WHERE loader_id=$1`, id)
	return err
}

func (r *LoaderRepo) Regenerate(ctx context.Context, oldID string) (string, error) {
	// Mark old inactive and increment version reference
	old, err := r.GetByID(ctx, oldID)
	if err != nil || old == nil {
		return "", errors.New("loader not found")
	}
	newID := "lk_" + randomHex(8)
	tx, err := r.db.BeginTxx(ctx, nil)
	if err != nil {
		return "", err
	}
	defer tx.Rollback()

	if _, err := tx.ExecContext(ctx,
		`UPDATE loaders SET is_active=FALSE, rotated_at=now() WHERE loader_id=$1`, oldID); err != nil {
		return "", err
	}
	now := time.Now()
	if _, err := tx.ExecContext(ctx, `INSERT INTO loaders
		(id,service_id,loader_id,version,mode,is_active,created_at)
		VALUES ($1,$2,$3,$4,$5,TRUE,$6)`,
		uuid.New(), old.ServiceID, newID, old.Version+1, old.Mode, now); err != nil {
		return "", err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO loader_configs
		(loader_id,trigger_type,trigger_value,cookie_name,respect_dnt,allow_bots,
		 js_file_alias,fbp_cookie_name,fbc_cookie_name,honor_consent,vendor_mapping,updated_at)
		SELECT $1, trigger_type, trigger_value, cookie_name, respect_dnt, allow_bots,
		       js_file_alias, fbp_cookie_name, fbc_cookie_name, honor_consent, vendor_mapping, $2
		FROM loader_configs WHERE loader_id=$3`, newID, now, oldID); err != nil {
		return "", err
	}
	if err := tx.Commit(); err != nil {
		return "", err
	}
	return newID, nil
}

func (r *LoaderRepo) IncrementHit(ctx context.Context, id string) error {
	_, err := r.db.ExecContext(ctx, `UPDATE loaders
		SET hit_count = hit_count + 1, last_hit_at = now()
		WHERE loader_id=$1`, id)
	return err
}