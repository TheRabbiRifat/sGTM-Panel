package repos

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
)

type UsageRepo struct{ db *sqlx.DB }

func NewUsageRepo(db *sqlx.DB) *UsageRepo { return &UsageRepo{db: db} }

// IncRequests increments the daily request counter for a service.
func (r *UsageRepo) IncRequests(ctx context.Context, serviceID uuid.UUID, n int) error {
	_, err := r.db.ExecContext(ctx, `INSERT INTO usage_daily (service_id, date, requests)
		VALUES ($1, CURRENT_DATE, $2)
		ON CONFLICT (service_id, date) DO UPDATE SET requests = usage_daily.requests + EXCLUDED.requests`,
		serviceID, n)
	return err
}

func (r *UsageRepo) IncBandwidth(ctx context.Context, serviceID uuid.UUID, bytes int64) error {
	_, err := r.db.ExecContext(ctx, `INSERT INTO usage_daily (service_id, date, bandwidth_b)
		VALUES ($1, CURRENT_DATE, $2)
		ON CONFLICT (service_id, date) DO UPDATE SET bandwidth_b = usage_daily.bandwidth_b + EXCLUDED.bandwidth_b`,
		serviceID, bytes)
	return err
}

func (r *UsageRepo) IncLoaderHits(ctx context.Context, serviceID uuid.UUID, n int) error {
	_, err := r.db.ExecContext(ctx, `INSERT INTO usage_daily (service_id, date, loader_hits)
		VALUES ($1, CURRENT_DATE, $2)
		ON CONFLICT (service_id, date) DO UPDATE SET loader_hits = usage_daily.loader_hits + EXCLUDED.loader_hits`,
		serviceID, n)
	return err
}

func (r *UsageRepo) IncCookieExtHits(ctx context.Context, serviceID uuid.UUID, n int) error {
	_, err := r.db.ExecContext(ctx, `INSERT INTO usage_daily (service_id, date, cookie_ext_hits)
		VALUES ($1, CURRENT_DATE, $2)
		ON CONFLICT (service_id, date) DO UPDATE SET cookie_ext_hits = usage_daily.cookie_ext_hits + EXCLUDED.cookie_ext_hits`,
		serviceID, n)
	return err
}

type DailyUsage struct {
	Date           time.Time `db:"date" json:"date"`
	Requests       int64     `db:"requests" json:"requests"`
	BandwidthB     int64     `db:"bandwidth_b" json:"bandwidth_b"`
	LoaderHits     int64     `db:"loader_hits" json:"loader_hits"`
	CookieExtHits  int64     `db:"cookie_ext_hits" json:"cookie_ext_hits"`
}

func (r *UsageRepo) Range(ctx context.Context, serviceID uuid.UUID, from, to time.Time) ([]DailyUsage, error) {
	var out []DailyUsage
	err := r.db.SelectContext(ctx, &out, `SELECT date, requests, bandwidth_b, loader_hits, cookie_ext_hits
		FROM usage_daily
		WHERE service_id=$1 AND date BETWEEN $2 AND $3
		ORDER BY date ASC`, serviceID, from, to)
	return out, err
}

func (r *UsageRepo) ThisMonth(ctx context.Context, serviceID uuid.UUID) (*DailyUsage, error) {
	var u DailyUsage
	err := r.db.GetContext(ctx, &u, `SELECT
		COALESCE(SUM(requests),0)        AS requests,
		COALESCE(SUM(bandwidth_b),0)     AS bandwidth_b,
		COALESCE(SUM(loader_hits),0)     AS loader_hits,
		COALESCE(SUM(cookie_ext_hits),0) AS cookie_ext_hits
		FROM usage_daily
		WHERE service_id=$1
		  AND date_trunc('month', date) = date_trunc('month', now())`, serviceID)
	if err != nil {
		return nil, err
	}
	return &u, nil
}