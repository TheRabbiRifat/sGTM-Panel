package provisioning

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"github.com/rs/zerolog"

	"github.com/hostaffin/sgtm/control-plane/internal/auth"
	"github.com/hostaffin/sgtm/control-plane/internal/config"
	"github.com/hostaffin/sgtm/control-plane/internal/domain"
	"github.com/hostaffin/sgtm/control-plane/internal/queue"
	"github.com/hostaffin/sgtm/control-plane/internal/repos"
)

// Service is the provisioning orchestrator.
type Service struct {
	cfg      *config.Config
	log      zerolog.Logger
	svc      *repos.ServiceRepo
	plan     *repos.PlanRepo
	node     *repos.NodeRepo
	loader   *repos.LoaderRepo
	cook     *repos.CookieExtRepo
	audit    *repos.AuditRepo
	queue    *queue.Asynq
}

// New returns a new provisioning Service.
func New(
	cfg *config.Config,
	log zerolog.Logger,
	svc *repos.ServiceRepo,
	plan *repos.PlanRepo,
	node *repos.NodeRepo,
	loader *repos.LoaderRepo,
	cook *repos.CookieExtRepo,
	audit *repos.AuditRepo,
	q *queue.Asynq,
) *Service {
	return &Service{cfg: cfg, log: log, svc: svc, plan: plan, node: node, loader: loader, cook: cook, audit: audit, queue: q}
}

type CreateCmd struct {
	WhmcsServiceID int
	WhmcsClientID  int
	PlanSlug       string
	Domain         string
}

// Create provisions a new sGTM service.
func (s *Service) Create(ctx context.Context, cmd CreateCmd) (*domain.Service, error) {
	plan, err := s.plan.GetBySlug(ctx, cmd.PlanSlug)
	if err != nil {
		return nil, err
	}
	if plan == nil {
		return nil, fmt.Errorf("plan not found: %s", cmd.PlanSlug)
	}

	svc := &domain.Service{
		WhmcsServiceID: cmd.WhmcsServiceID,
		WhmcsClientID:  cmd.WhmcsClientID,
		PlanID:         plan.ID,
		Status:         domain.ServicePending,
		EdgeHostname:   generateEdgeHostname(s.cfg.EdgeDomain),
	}
	if err := s.svc.Create(ctx, svc); err != nil {
		return nil, err
	}

	// Pick a node
	node, err := s.schedulerPick(ctx, plan)
	if err != nil {
		return nil, err
	}
	if node != nil {
		_ = s.svc.SetNodeID(ctx, svc.ID, node.ID)
		svc.NodeID = &node.ID
	}

	// Create the default Custom Loader
	loader := &domain.Loader{
		ServiceID: svc.ID,
		Mode:      domain.LoaderLive,
		IsActive:  true,
	}
	cfg := &domain.LoaderConfig{
		TriggerType: "immediate",
		RespectDNT:  true,
		AllowBots:   false,
	}
	if err := s.loader.Create(ctx, loader, cfg); err != nil {
		s.log.Warn().Err(err).Msg("loader create failed")
	}

	// Enqueue async provisioning job
	payload, _ := json.Marshal(map[string]any{"service_id": svc.ID.String()})
	if err := s.queue.Enqueue(ctx, "service:provision", payload); err != nil {
		s.log.Error().Err(err).Msg("enqueue provision")
	}

	_ = s.audit.Log(ctx, repos.AuditEntry{
		ActorType: "system",
		Action:    "service.create",
		Resource:  "service:" + svc.ID.String(),
		Metadata:  map[string]any{"plan": plan.Slug, "whmcs_service_id": cmd.WhmcsServiceID},
	})

	return svc, nil
}

// schedulerPick finds the best node for a plan.
func (s *Service) schedulerPick(ctx context.Context, plan *domain.Plan) (*domain.Node, error) {
	nodes, err := s.node.ListOnline(ctx)
	if err != nil {
		return nil, err
	}
	best := (*domain.Node)(nil)
	bestScore := 2.0
	for i := range nodes {
		n := nodes[i]
		if n.TotalCPU == nil || n.TotalRAMMB == nil {
			continue
		}
		availCPU := *n.TotalCPU - n.UsedCPU
		availRAM := float64(*n.TotalRAMMB - n.UsedRAMMB)
		if availCPU < plan.CPULimit {
			continue
		}
		if availRAM < float64(plan.RAMLimitMB) {
			continue
		}
		score := (n.UsedCPU / *n.TotalCPU)
		if score < bestScore {
			bestScore = score
			best = &n
		}
	}
	return best, nil
}

// Restart restarts a service.
func (s *Service) Restart(ctx context.Context, id uuid.UUID, actor string) error {
	svc, err := s.svc.GetByID(ctx, id)
	if err != nil {
		return err
	}
	if svc == nil {
		return errors.New("service not found")
	}
	payload, _ := json.Marshal(map[string]any{"service_id": id.String()})
	if err := s.queue.Enqueue(ctx, "service:restart", payload); err != nil {
		return err
	}
	_ = s.audit.Log(ctx, repos.AuditEntry{
		ActorType: actor,
		Action:    "service.restart",
		Resource:  "service:" + id.String(),
	})
	return nil
}

// Suspend scales the service down and marks it suspended.
func (s *Service) Suspend(ctx context.Context, id uuid.UUID, actor, reason string) error {
	if err := s.svc.UpdateStatus(ctx, id, domain.ServiceSuspended, nil); err != nil {
		return err
	}
	payload, _ := json.Marshal(map[string]any{"service_id": id.String(), "action": "suspend"})
	_ = s.queue.Enqueue(ctx, "service:container", payload)
	_ = s.audit.Log(ctx, repos.AuditEntry{
		ActorType: actor, Action: "service.suspend", Resource: "service:" + id.String(),
		Metadata: map[string]any{"reason": reason},
	})
	return nil
}

// Unsuspend resumes the service.
func (s *Service) Unsuspend(ctx context.Context, id uuid.UUID, actor string) error {
	if err := s.svc.UpdateStatus(ctx, id, domain.ServiceActive, nil); err != nil {
		return err
	}
	payload, _ := json.Marshal(map[string]any{"service_id": id.String(), "action": "unsuspend"})
	_ = s.queue.Enqueue(ctx, "service:container", payload)
	_ = s.audit.Log(ctx, repos.AuditEntry{
		ActorType: actor, Action: "service.unsuspend", Resource: "service:" + id.String(),
	})
	return nil
}

// Terminate permanently destroys the service.
func (s *Service) Terminate(ctx context.Context, id uuid.UUID, actor string) error {
	if err := s.svc.UpdateStatus(ctx, id, domain.ServiceTerminated, nil); err != nil {
		return err
	}
	payload, _ := json.Marshal(map[string]any{"service_id": id.String(), "action": "terminate"})
	_ = s.queue.Enqueue(ctx, "service:container", payload)
	_ = s.audit.Log(ctx, repos.AuditEntry{
		ActorType: actor, Action: "service.terminate", Resource: "service:" + id.String(),
	})
	return nil
}

// Upgrade changes the plan and resizes the container.
func (s *Service) Upgrade(ctx context.Context, id uuid.UUID, planSlug, actor string) error {
	plan, err := s.plan.GetBySlug(ctx, planSlug)
	if err != nil || plan == nil {
		return fmt.Errorf("plan not found: %s", planSlug)
	}
	if err := s.svc.UpdatePlan(ctx, id, plan.ID); err != nil {
		return err
	}
	payload, _ := json.Marshal(map[string]any{"service_id": id.String(), "plan_slug": planSlug})
	_ = s.queue.Enqueue(ctx, "service:upgrade", payload)
	_ = s.audit.Log(ctx, repos.AuditEntry{
		ActorType: actor, Action: "service.upgrade", Resource: "service:" + id.String(),
		Metadata: map[string]any{"new_plan": planSlug},
	})
	return nil
}

// MoveNode relocates a service to another node.
func (s *Service) MoveNode(ctx context.Context, id, nodeID uuid.UUID, actor string) error {
	if err := s.svc.SetNodeID(ctx, id, nodeID); err != nil {
		return err
	}
	payload, _ := json.Marshal(map[string]any{"service_id": id.String(), "action": "move", "node_id": nodeID.String()})
	_ = s.queue.Enqueue(ctx, "service:container", payload)
	_ = s.audit.Log(ctx, repos.AuditEntry{
		ActorType: actor, Action: "service.move", Resource: "service:" + id.String(),
		Metadata: map[string]any{"node_id": nodeID.String()},
	})
	return nil
}

// generateEdgeHostname returns a 16-hex-char edge hostname under edgeDomain.
func generateEdgeHostname(edgeDomain string) string {
	if edgeDomain == "" {
		edgeDomain = "edge.hostaffin.local"
	}
	// 16 hex chars = 8 bytes of entropy, e.g. "8f3a2c1b9d4e5f6a"
	hex := auth.RandomToken(12) // 16 base64url chars; URL-safe
	// strip any non-alnum for safety
	out := make([]byte, 0, len(hex))
	for i := 0; i < len(hex) && len(out) < 16; i++ {
		c := hex[i]
		switch {
		case c >= '0' && c <= '9', c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z':
			out = append(out, c)
		}
	}
	return string(out) + "." + edgeDomain
}