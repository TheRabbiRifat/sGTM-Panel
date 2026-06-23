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

const chromeLifetimeCap = 34190000 // 395 days

type CookieExtRepo struct{ db *sqlx.DB }

func NewCookieExtRepo(db *sqlx.DB) *CookieExtRepo { return &CookieExtRepo{db: db} }

func (r *CookieExtRepo) Create(ctx context.Context, c *domain.CookieExtension) error {
	if c.ID == uuid.Nil {
		c.ID = uuid.New()
	}
	if c.NewLifetimeS > chromeLifetimeCap {
		c.NewLifetimeS = chromeLifetimeCap
	}
	if c.Path == "" {
		c.Path = "/"
	}
	if c.SameSite == "" {
		c.SameSite = "Lax"
	}
	now := time.Now()
	c.CreatedAt, c.UpdatedAt = now, now
	_, err := r.db.NamedExecContext(ctx, `INSERT INTO cookie_extensions
		(id,service_id,cookie_name,vendor_url,new_lifetime_s,cookie_domain,path,
		 secure,http_only,same_site,is_active,hit_count,created_at,updated_at)
		VALUES (:id,:service_id,:cookie_name,:vendor_url,:new_lifetime_s,:cookie_domain,:path,
		        :secure,:http_only,:same_site,:is_active,:hit_count,:created_at,:updated_at)`, c)
	return err
}

func (r *CookieExtRepo) GetByID(ctx context.Context, id uuid.UUID) (*domain.CookieExtension, error) {
	var c domain.CookieExtension
	err := r.db.GetContext(ctx, &c, `SELECT * FROM cookie_extensions WHERE id=$1`, id)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return &c, err
}

func (r *CookieExtRepo) GetByName(ctx context.Context, serviceID uuid.UUID, name string) (*domain.CookieExtension, error) {
	var c domain.CookieExtension
	err := r.db.GetContext(ctx, &c,
		`SELECT * FROM cookie_extensions WHERE service_id=$1 AND cookie_name=$2`, serviceID, name)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return &c, err
}

func (r *CookieExtRepo) ListByService(ctx context.Context, serviceID uuid.UUID) ([]domain.CookieExtension, error) {
	var out []domain.CookieExtension
	err := r.db.SelectContext(ctx, &out,
		`SELECT * FROM cookie_extensions WHERE service_id=$1 ORDER BY cookie_name`, serviceID)
	return out, err
}

func (r *CookieExtRepo) Update(ctx context.Context, c *domain.CookieExtension) error {
	if c.NewLifetimeS > chromeLifetimeCap {
		c.NewLifetimeS = chromeLifetimeCap
	}
	_, err := r.db.NamedExecContext(ctx, `UPDATE cookie_extensions SET
		vendor_url=:vendor_url,
		new_lifetime_s=:new_lifetime_s,
		cookie_domain=:cookie_domain,
		path=:path,
		secure=:secure,
		http_only=:http_only,
		same_site=:same_site,
		is_active=:is_active,
		updated_at=now()
		WHERE id=:id`, c)
	return err
}

func (r *CookieExtRepo) Delete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `DELETE FROM cookie_extensions WHERE id=$1`, id)
	return err
}

func (r *CookieExtRepo) IncrementHit(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `UPDATE cookie_extensions
		SET hit_count = hit_count + 1, last_used_at = now() WHERE id=$1`, id)
	return err
}

func (r *CookieExtRepo) LogHit(ctx context.Context, extID uuid.UUID, status int, ipHash, ua string, bytesIn, bytesOut int) error {
	_, err := r.db.ExecContext(ctx, `INSERT INTO cookie_extension_logs
		(cookie_ext_id, ts, status_code, source_ip_hash, user_agent, bytes_in, bytes_out)
		VALUES ($1, now(), $2, $3, $4, $5, $6)`, extID, status, ipHash, ua, bytesIn, bytesOut)
	return err
}

func (r *CookieExtRepo) RecentLogs(ctx context.Context, serviceID uuid.UUID, limit int) ([]CookieExtLog, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	var out []CookieExtLog
	err := r.db.SelectContext(ctx, &out, `SELECT l.* FROM cookie_extension_logs l
		JOIN cookie_extensions c ON c.id = l.cookie_ext_id
		WHERE c.service_id=$1
		ORDER BY l.ts DESC LIMIT $2`, serviceID, limit)
	return out, err
}

func (r *CookieExtRepo) PurgeOldLogs(ctx context.Context, olderThan time.Duration) (int64, error) {
	res, err := r.db.ExecContext(ctx, `DELETE FROM cookie_extension_logs
		WHERE ts < now() - $1::interval`, olderThan.String())
	if err != nil {
		return 0, err
	}
	return res.RowsAffected()
}

type CookieExtLog struct {
	ID          int64      `db:"id" json:"id"`
	CookieExtID uuid.UUID  `db:"cookie_ext_id" json:"cookie_ext_id"`
	TS          time.Time  `db:"ts" json:"ts"`
	StatusCode  *int       `db:"status_code" json:"status_code"`
	SourceIPHash *string   `db:"source_ip_hash" json:"source_ip_hash,omitempty"`
	UserAgent   *string    `db:"user_agent" json:"user_agent,omitempty"`
	BytesIn     *int       `db:"bytes_in" json:"bytes_in"`
	BytesOut    *int       `db:"bytes_out" json:"bytes_out"`
}