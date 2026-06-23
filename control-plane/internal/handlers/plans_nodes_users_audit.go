package handlers

import (
	"strconv"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"

	"github.com/hostaffin/sgtm/control-plane/internal/auth"
	"github.com/hostaffin/sgtm/control-plane/internal/domain"
)

func hashPassword(p string) (string, error) { return auth.HashPassword(p) }

type PlanHandler struct{ d *Deps }

func NewPlanHandler(d *Deps) *PlanHandler { return &PlanHandler{d: d} }

func (h *PlanHandler) List(c *fiber.Ctx) error {
	activeOnly := c.Query("active") == "true"
	out, err := newPlanRepo(h.d).List(c.Context(), activeOnly)
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{"items": out})
}

func (h *PlanHandler) Create(c *fiber.Ctx) error {
	var p domain.Plan
	if err := c.BodyParser(&p); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid body")
	}
	if err := newPlanRepo(h.d).Upsert(c.Context(), &p); err != nil {
		return err
	}
	return c.Status(201).JSON(p)
}

func (h *PlanHandler) Update(c *fiber.Ctx) error {
	id, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid id")
	}
	var p domain.Plan
	if err := c.BodyParser(&p); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid body")
	}
	p.ID = id
	if err := newPlanRepo(h.d).Upsert(c.Context(), &p); err != nil {
		return err
	}
	return c.JSON(p)
}

type NodeHandler struct{ d *Deps }

func NewNodeHandler(d *Deps) *NodeHandler { return &NodeHandler{d: d} }

func (h *NodeHandler) List(c *fiber.Ctx) error {
	out, err := newNodeRepo(h.d).List(c.Context())
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{"items": out})
}

func (h *NodeHandler) Create(c *fiber.Ctx) error {
	var n domain.Node
	if err := c.BodyParser(&n); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid body")
	}
	if n.Status == "" {
		n.Status = domain.NodeOffline
	}
	if err := newNodeRepo(h.d).Upsert(c.Context(), &n); err != nil {
		return err
	}
	return c.Status(201).JSON(n)
}

func (h *NodeHandler) Drain(c *fiber.Ctx) error { return setNodeStatus(c, h.d, domain.NodeDraining) }
func (h *NodeHandler) Maintenance(c *fiber.Ctx) error {
	return setNodeStatus(c, h.d, domain.NodeMaintenance)
}
func (h *NodeHandler) Enable(c *fiber.Ctx) error  { return setNodeStatus(c, h.d, domain.NodeOnline) }

func setNodeStatus(c *fiber.Ctx, d *Deps, status domain.NodeStatus) error {
	id, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid id")
	}
	n, err := newNodeRepo(d).GetByID(c.Context(), id)
	if err != nil || n == nil {
		return fiber.NewError(fiber.StatusNotFound, "node not found")
	}
	n.Status = status
	if err := newNodeRepo(d).Upsert(c.Context(), n); err != nil {
		return err
	}
	actor := "admin"
	if cl := auth.MustClaims(c); cl != nil {
		actor = cl.Email
	}
	_ = newAuditRepo(d).Log(c.Context(), auditEntry(actor, "node."+string(status), "node:"+id.String(), nil))
	return c.JSON(fiber.Map{"ok": true, "status": status})
}

type UserHandler struct{ d *Deps }

func NewUserHandler(d *Deps) *UserHandler { return &UserHandler{d: d} }

func (h *UserHandler) List(c *fiber.Ctx) error {
	limit, _ := strconv.Atoi(c.Query("limit", "50"))
	offset, _ := strconv.Atoi(c.Query("offset", "0"))
	out, err := newUserRepo(h.d).List(c.Context(), limit, offset)
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{"items": out})
}

func (h *UserHandler) Create(c *fiber.Ctx) error {
	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
		Role     string `json:"role"`
	}
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid body")
	}
	hash, err := hashPassword(req.Password)
	if err != nil {
		return err
	}
	u := &domain.User{
		Email:    req.Email,
		Password: hash,
		Role:     domain.Role(req.Role),
		IsActive: true,
	}
	if err := newUserRepo(h.d).Create(c.Context(), u); err != nil {
		return fiber.NewError(fiber.StatusConflict, err.Error())
	}
	return c.Status(201).JSON(u)
}

func (h *UserHandler) Update(c *fiber.Ctx) error {
	id, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid id")
	}
	var req struct {
		Role     *string `json:"role,omitempty"`
		IsActive *bool   `json:"is_active,omitempty"`
		Password *string `json:"password,omitempty"`
	}
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid body")
	}
	repo := newUserRepo(h.d)
	u, err := repo.GetByID(c.Context(), id)
	if err != nil || u == nil {
		return fiber.NewError(fiber.StatusNotFound, "user not found")
	}
	if req.Role != nil {
		u.Role = domain.Role(*req.Role)
	}
	if req.IsActive != nil {
		u.IsActive = *req.IsActive
	}
	if req.Password != nil {
		hash, err := hashPassword(*req.Password)
		if err != nil {
			return err
		}
		u.Password = hash
	}
	if _, err := repo.UpdateLastLogin(c.Context(), u.ID); err != nil {
		return err
	}
	// direct update via DB
	if _, err := h.d.DB.ExecContext(c.Context(),
		`UPDATE users SET role=$1, is_active=$2, password=$3 WHERE id=$4`,
		u.Role, u.IsActive, u.Password, u.ID); err != nil {
		return err
	}
	return c.JSON(u)
}

type AuditHandler struct{ d *Deps }

func NewAuditHandler(d *Deps) *AuditHandler { return &AuditHandler{d: d} }

func (h *AuditHandler) List(c *fiber.Ctx) error {
	limit, _ := strconv.Atoi(c.Query("limit", "50"))
	offset, _ := strconv.Atoi(c.Query("offset", "0"))
	out, err := newAuditRepo(h.d).List(c.Context(), limit, offset)
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{"items": out})
}