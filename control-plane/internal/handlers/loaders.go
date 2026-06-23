package handlers

import (
	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"

	"github.com/hostaffin/sgtm/control-plane/internal/auth"
	"github.com/hostaffin/sgtm/control-plane/internal/domain"
	ldsvc "github.com/hostaffin/sgtm/control-plane/internal/services/loaders"
)

type LoaderHandler struct {
	d   *Deps
	svc *ldsvc.Service
}

func NewLoaderHandler(d *Deps) *LoaderHandler {
	return &LoaderHandler{
		d: d,
		svc: ldsvc.New(newLoaderRepo(d), newAuditRepo(d), d.Queue, d.Log),
	}
}

func (h *LoaderHandler) List(c *fiber.Ctx) error {
	sid, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid id")
	}
	out, err := h.svc.List(c.Context(), sid)
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{"items": out})
}

type createLoaderReq struct {
	Mode         domain.LoaderMode `json:"mode"`
	TriggerType  string            `json:"trigger_type"`
	TriggerValue string            `json:"trigger_value"`
	CookieName   string            `json:"cookie_name"`
	RespectDNT   *bool             `json:"respect_dnt"`
	AllowBots    *bool             `json:"allow_bots"`
}

func (h *LoaderHandler) Create(c *fiber.Ctx) error {
	sid, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid service id")
	}
	var req createLoaderReq
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid body")
	}
	mode := req.Mode
	if mode == "" {
		mode = domain.LoaderLive
	}
	respect := true
	if req.RespectDNT != nil {
		respect = *req.RespectDNT
	}
	allow := false
	if req.AllowBots != nil {
		allow = *req.AllowBots
	}
	l := &domain.Loader{ServiceID: sid, Mode: mode, IsActive: true}
	cfg := &domain.LoaderConfig{
		TriggerType:  req.TriggerType,
		TriggerValue: req.TriggerValue,
		CookieName:   req.CookieName,
		RespectDNT:   respect,
		AllowBots:    allow,
	}
	if err := h.svc.Create(c.Context(), l, cfg); err != nil {
		return fiber.NewError(fiber.StatusUnprocessableEntity, err.Error())
	}
	return c.Status(201).JSON(fiber.Map{
		"loader": l,
		"config": cfg,
		"snippet": ldsvc.RenderLoader(l.LoaderID, cfg),
		"sri_hash": ldsvc.ComputeSRI(ldsvc.RenderLoader(l.LoaderID, cfg)),
	})
}

func (h *LoaderHandler) Get(c *fiber.Ctx) error {
	id := c.Params("loader_id")
	l, cfg, err := h.svc.Get(c.Context(), id)
	if err != nil {
		return err
	}
	if l == nil {
		return fiber.NewError(fiber.StatusNotFound, "loader not found")
	}
	snippet := ldsvc.RenderLoader(id, cfg)
	return c.JSON(fiber.Map{
		"loader":   l,
		"config":   cfg,
		"snippet":  snippet,
		"sri_hash": ldsvc.ComputeSRI(snippet),
	})
}

func (h *LoaderHandler) UpdateConfig(c *fiber.Ctx) error {
	id := c.Params("loader_id")
	var req struct {
		TriggerType  string `json:"trigger_type"`
		TriggerValue string `json:"trigger_value"`
		CookieName   string `json:"cookie_name"`
		RespectDNT   *bool  `json:"respect_dnt"`
		AllowBots    *bool  `json:"allow_bots"`
	}
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid body")
	}
	cfg, err := newLoaderRepo(h.d).GetConfig(c.Context(), id)
	if err != nil || cfg == nil {
		return fiber.NewError(fiber.StatusNotFound, "loader not found")
	}
	if req.TriggerType != "" {
		cfg.TriggerType = req.TriggerType
	}
	cfg.TriggerValue = req.TriggerValue
	cfg.CookieName = req.CookieName
	if req.RespectDNT != nil {
		cfg.RespectDNT = *req.RespectDNT
	}
	if req.AllowBots != nil {
		cfg.AllowBots = *req.AllowBots
	}
	if err := h.svc.UpdateConfig(c.Context(), cfg); err != nil {
		return err
	}
	return c.JSON(cfg)
}

func (h *LoaderHandler) Regenerate(c *fiber.Ctx) error {
	id := c.Params("loader_id")
	actor := "admin"
	if cl := auth.MustClaims(c); cl != nil {
		actor = cl.Email
	}
	newID, err := h.svc.Regenerate(c.Context(), id, actor)
	if err != nil {
		return fiber.NewError(fiber.StatusUnprocessableEntity, err.Error())
	}
	return c.JSON(fiber.Map{"old_id": id, "new_id": newID})
}

func (h *LoaderHandler) Disable(c *fiber.Ctx) error {
	id := c.Params("loader_id")
	actor := "admin"
	if cl := auth.MustClaims(c); cl != nil {
		actor = cl.Email
	}
	if err := h.svc.Disable(c.Context(), id, actor); err != nil {
		return err
	}
	return c.JSON(fiber.Map{"ok": true})
}

func (h *LoaderHandler) Analytics(c *fiber.Ctx) error {
	id := c.Params("loader_id")
	l, err := newLoaderRepo(h.d).GetByID(c.Context(), id)
	if err != nil || l == nil {
		return fiber.NewError(fiber.StatusNotFound, "loader not found")
	}
	return c.JSON(fiber.Map{
		"loader_id": id,
		"hit_count": l.HitCount,
		"last_hit":  l.LastHitAt,
		"is_active": l.IsActive,
	})
}