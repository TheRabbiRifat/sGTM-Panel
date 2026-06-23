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

type UserRepo struct{ db *sqlx.DB }

func NewUserRepo(db *sqlx.DB) *UserRepo { return &UserRepo{db: db} }

func (r *UserRepo) GetByEmail(ctx context.Context, email string) (*domain.User, error) {
	var u domain.User
	err := r.db.GetContext(ctx, &u, `SELECT * FROM users WHERE email=$1`, email)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return &u, err
}

func (r *UserRepo) GetByID(ctx context.Context, id uuid.UUID) (*domain.User, error) {
	var u domain.User
	err := r.db.GetContext(ctx, &u, `SELECT * FROM users WHERE id=$1`, id)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return &u, err
}

func (r *UserRepo) Create(ctx context.Context, u *domain.User) error {
	if u.ID == uuid.Nil {
		u.ID = uuid.New()
	}
	now := time.Now()
	u.CreatedAt, u.UpdatedAt = now, now
	_, err := r.db.NamedExecContext(ctx, `INSERT INTO users
		(id,email,password,role,whmcs_client_id,is_active,created_at,updated_at)
		VALUES (:id,:email,:password,:role,:whmcs_client_id,:is_active,:created_at,:updated_at)`, u)
	return err
}

func (r *UserRepo) UpdateLastLogin(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `UPDATE users SET last_login_at=now() WHERE id=$1`, id)
	return err
}

func (r *UserRepo) List(ctx context.Context, limit, offset int) ([]domain.User, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	var out []domain.User
	err := r.db.SelectContext(ctx, &out, `SELECT * FROM users ORDER BY created_at DESC LIMIT $1 OFFSET $2`, limit, offset)
	return out, err
}