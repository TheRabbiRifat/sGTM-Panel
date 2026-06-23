package repos

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"

	"github.com/hostaffin/sgtm/control-plane/internal/domain"
)

type ServiceRepo struct{ db *sqlx.DB }

func NewServiceRepo(db *sqlx.DB) *ServiceRepo { return &ServiceRepo{db: db} }

func (r *ServiceRepo) Create(ctx context.Context, s *domain.Service) error {
	if s.ID == uuid.Nil {
		s.ID = uuid.New()
	}
	now := time.Now()
	s.CreatedAt, s.UpdatedAt = now, now
	_, err := r.db.NamedExecContext(ctx, `INSERT INTO services
		(id,whmcs_service_id,whmcs_client_id,plan_id,node_id,status,edge_hostname,
		 container_id,container_name,overage,activated_at)
		VALUES (:id,:whmcs_service_id,:whmcs_client_id,:plan_id,:node_id,:status,:edge_hostname,
		        :container_id,:container_name,:overage,:activated_at)`, s)
	return err
}

func (r *ServiceRepo) GetByID(ctx context.Context, id uuid.UUID) (*domain.Service, error) {
	var s domain.Service
	err := r.db.GetContext(ctx, &s, `SELECT * FROM services WHERE id=$1`, id)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return &s, err
}

func (r *ServiceRepo) GetByWhmcsServiceID(ctx context.Context, whmcsID int) (*domain.Service, error) {
	var s domain.Service
	err := r.db.GetContext(ctx, &s, `SELECT * FROM services WHERE whmcs_service_id=$1`, whmcsID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return &s, err
}

func (r *ServiceRepo) GetByEdgeHostname(ctx context.Context, h string) (*domain.Service, error) {
	var s domain.Service
	err := r.db.GetContext(ctx, &s, `SELECT * FROM services WHERE edge_hostname=$1`, h)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return &s, err
}

type ServiceFilter struct {
	Status        string
	PlanID        *uuid.UUID
	NodeID        *uuid.UUID
	WhmcsClientID *int
	Search        string
	Limit         int
	Offset        int
}

func (r *ServiceRepo) List(ctx context.Context, f ServiceFilter) ([]domain.Service, error) {
	conds := []string{"1=1"}
	args := []interface{}{}
	idx := 1
	if f.Status != "" {
		conds = append(conds, "status=$"+itoa(idx))
		args = append(args, f.Status)
		idx++
	}
	if f.PlanID != nil {
		conds = append(conds, "plan_id=$"+itoa(idx))
		args = append(args, *f.PlanID)
		idx++
	}
	if f.NodeID != nil {
		conds = append(conds, "node_id=$"+itoa(idx))
		args = append(args, *f.NodeID)
		idx++
	}
	if f.WhmcsClientID != nil {
		conds = append(conds, "whmcs_client_id=$"+itoa(idx))
		args = append(args, *f.WhmcsClientID)
		idx++
	}
	if f.Search != "" {
		conds = append(conds, "(edge_hostname ILIKE '%' || $"+itoa(idx)+" || '%' OR id::text=$"+itoa(idx)+")")
		args = append(args, f.Search)
		idx++
	}
	limit := f.Limit
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	q := "SELECT * FROM services WHERE " + strings.Join(conds, " AND ") + " ORDER BY created_at DESC LIMIT " + itoa(limit) + " OFFSET " + itoa(f.Offset)
	var out []domain.Service
	err := r.db.SelectContext(ctx, &out, q, args...)
	return out, err
}

func (r *ServiceRepo) UpdateStatus(ctx context.Context, id uuid.UUID, status domain.ServiceStatus, reason *string) error {
	q := `UPDATE services SET status=$2, updated_at=now()`
	args := []interface{}{id, status}
	if reason != nil {
		q += `, failure_reason=$3`
		args = append(args, *reason)
	}
	if status == domain.ServiceActive {
		q += `, activated_at=COALESCE(activated_at, now())`
	}
	if status == domain.ServiceTerminated {
		q += `, terminated_at=now()`
	}
	q += ` WHERE id=$1`
	_, err := r.db.ExecContext(ctx, q, args...)
	return err
}

func (r *ServiceRepo) UpdatePlan(ctx context.Context, id uuid.UUID, planID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `UPDATE services SET plan_id=$2, updated_at=now() WHERE id=$1`, id, planID)
	return err
}

func (r *ServiceRepo) UpdateContainer(ctx context.Context, id uuid.UUID, containerID, containerName string) error {
	_, err := r.db.ExecContext(ctx, `UPDATE services
		SET container_id=$2, container_name=$3, updated_at=now()
		WHERE id=$1`, id, containerID, containerName)
	return err
}

func (r *ServiceRepo) SetNodeID(ctx context.Context, id uuid.UUID, nodeID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `UPDATE services SET node_id=$2, updated_at=now() WHERE id=$1`, id, nodeID)
	return err
}

func (r *ServiceRepo) SetOverage(ctx context.Context, id uuid.UUID, overage bool) error {
	_, err := r.db.ExecContext(ctx, `UPDATE services SET overage=$2, updated_at=now() WHERE id=$1`, id, overage)
	return err
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var b [20]byte
	i := len(b)
	for n > 0 {
		i--
		b[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}