package handlers

import (
	"strconv"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"

	prov "github.com/hostaffin/sgtm/control-plane/internal/services/provisioning"
)

type ServiceHandler struct {
	d   *Deps
	svc *prov.Service
}

func NewServiceHandler(d *Deps) *ServiceHandler {
	return &ServiceHandler{
		d: d,
		svc: prov.New(
			d.Cfg, d.Log,
			newServiceRepo(d), newPlanRepo(d), newNodeRepo(d),
			newLoaderRepo(d), newCookieExtRepo(d), newAuditRepo(d), d.Queue,
		),
	}
}

type createServiceReq struct {
	WhmcsServiceID int    `json:"whmcs_service_id"`
	WhmcsClientID  int    `json:"whmcs_client_id"`
	PlanSlug       string `json:"plan_slug"`
	Domain         string `json:"domain"`
}

func (h *ServiceHandler) Create(c *fiber.Ctx) error {
	var req createServiceReq
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid body")
	}
	if req.PlanSlug == "" {
		return fiber.NewError(fiber.StatusBadRequest, "plan_slug required")
	}
	s, err := h.svc.Create(c.Context(), prov.CreateCmd{
		WhmcsServiceID: req.WhmcsServiceID,
		WhmcsClientID:  req.WhmcsClientID,
		PlanSlug:       req.PlanSlug,
		Domain:         req.Domain,
	})
	if err != nil {
		return fiber.NewError(fiber.StatusUnprocessableEntity, err.Error())
	}
	return c.Status(201).JSON(s)
}

func (h *ServiceHandler) List(c *fiber.Ctx) error {
	repo := newServiceRepo(h.d)
	filter := serviceFilterFromQuery(c)
	out, err := repo.List(c.Context(), filter)
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{"items": out, "count": len(out)})
}

func (h *ServiceHandler) Get(c *fiber.Ctx) error {
	id, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid id")
	}
	repo := newServiceRepo(h.d)
	s, err := repo.GetByID(c.Context(), id)
	if err != nil {
		return err
	}
	if s == nil {
		return fiber.NewError(fiber.StatusNotFound, "service not found")
	}
	return c.JSON(s)
}

func (h *ServiceHandler) Usage(c *fiber.Ctx) error {
	id, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid id")
	}
	usageRepo := newUsageRepo(h.d)
	now := time.Now().UTC()
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.UTC)
	items, err := usageRepo.Range(c.Context(), id, monthStart, now)
	if err != nil {
		return err
	}
	thisMonth, _ := usageRepo.ThisMonth(c.Context(), id)
	return c.JSON(fiber.Map{"days": items, "month": thisMonth})
}

func (h *ServiceHandler) Metrics(c *fiber.Ctx) error {
	id, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid id")
	}
	// For v1, just return usage-derived metrics
	h.d.Log.Debug().Str("id", id.String()).Msg("metrics requested")
	return c.JSON(fiber.Map{"service_id": id, "note": "see /usage"})
}

func (h *ServiceHandler) Restart(c *fiber.Ctx) error {
	return runLifecycle(h, c, "restart")
}
func (h *ServiceHandler) Suspend(c *fiber.Ctx) error { return runLifecycle(h, c, "suspend") }
func (h *ServiceHandler) Unsuspend(c *fiber.Ctx) error {
	return runLifecycle(h, c, "unsuspend")
}
func (h *ServiceHandler) Terminate(c *fiber.Ctx) error { return runLifecycle(h, c, "terminate") }
func (h *ServiceHandler) Upgrade(c *fiber.Ctx) error  { return runLifecycle(h, c, "upgrade") }
func (h *ServiceHandler) Move(c *fiber.Ctx) error     { return runLifecycle(h, c, "move") }

func runLifecycle(h *ServiceHandler, c *fiber.Ctx, action string) error {
	id, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid id")
	}
	actor := "admin"
	if v := c.Locals("auth_claims"); v != nil {
		actor = "admin"
	}
	switch action {
	case "restart":
		err = h.svc.Restart(c.Context(), id, actor)
	case "suspend":
		err = h.svc.Suspend(c.Context(), id, actor, "")
	case "unsuspend":
		err = h.svc.Unsuspend(c.Context(), id, actor)
	case "terminate":
		err = h.svc.Terminate(c.Context(), id, actor)
	case "upgrade":
		var req struct{ PlanSlug string `json:"plan_slug"` }
		_ = c.BodyParser(&req)
		if req.PlanSlug == "" {
			return fiber.NewError(fiber.StatusBadRequest, "plan_slug required")
		}
		err = h.svc.Upgrade(c.Context(), id, req.PlanSlug, actor)
	case "move":
		var req struct {
			NodeID string `json:"node_id"`
		}
		_ = c.BodyParser(&req)
		nodeID, perr := uuid.Parse(req.NodeID)
		if perr != nil {
			return fiber.NewError(fiber.StatusBadRequest, "node_id required (uuid)")
		}
		err = h.svc.MoveNode(c.Context(), id, nodeID, actor)
	}
	if err != nil {
		return fiber.NewError(fiber.StatusUnprocessableEntity, err.Error())
	}
	return c.JSON(fiber.Map{"ok": true, "action": action})
}

func serviceFilterFromQuery(c *fiber.Ctx) serviceFilter {
	f := serviceFilter{Limit: 50}
	if s := c.Query("status"); s != "" {
		f.Status = s
	}
	if s := c.Query("search"); s != "" {
		f.Search = s
	}
	if s := c.Query("whmcs_client_id"); s != "" {
		if n, err := strconv.Atoi(s); err == nil {
			f.WhmcsClientID = &n
		}
	}
	if s := c.Query("plan_id"); s != "" {
		if u, err := uuid.Parse(s); err == nil {
			f.PlanID = &u
		}
	}
	if s := c.Query("node_id"); s != "" {
		if u, err := uuid.Parse(s); err == nil {
			f.NodeID = &u
		}
	}
	if s := c.Query("limit"); s != "" {
		if n, err := strconv.Atoi(s); err == nil {
			f.Limit = n
		}
	}
	if s := c.Query("offset"); s != "" {
		if n, err := strconv.Atoi(s); err == nil {
			f.Offset = n
		}
	}
	return f
}

type serviceFilter = struct {
	Status        string
	PlanID        *uuid.UUID
	NodeID        *uuid.UUID
	WhmcsClientID *int
	Search        string
	Limit         int
	Offset        int
}