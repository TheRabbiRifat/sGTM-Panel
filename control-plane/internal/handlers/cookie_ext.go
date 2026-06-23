package handlers

import (
	"strconv"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"

	"github.com/hostaffin/sgtm/control-plane/internal/auth"
	"github.com/hostaffin/sgtm/control-plane/internal/domain"
	cesvc "github.com/hostaffin/sgtm/control-plane/internal/services/cookie_ext"
)

type CookieExtHandler struct {
	d   *Deps
	svc *cesvc.Service
}

func NewCookieExtHandler(d *Deps) *CookieExtHandler {
	return &CookieExtHandler{
		d: d,
		svc: cesvc.New(newCookieExtRepo(d), newAuditRepo(d), d.Log),
	}
}

func (h *CookieExtHandler) List(c *fiber.Ctx) error {
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

type createCookieExtReq struct {
	CookieName   string  `json:"cookie_name"`
	VendorURL    string  `json:"vendor_url"`
	NewLifetimeS int     `json:"new_lifetime_s"`
	CookieDomain *string `json:"cookie_domain,omitempty"`
	Path         string  `json:"path"`
	Secure       *bool   `json:"secure"`
	HTTPOnly     *bool   `json:"http_only"`
	SameSite     string  `json:"same_site"`
}

func (h *CookieExtHandler) Create(c *fiber.Ctx) error {
	sid, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid service id")
	}
	var req createCookieExtReq
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid body")
	}
	if req.CookieName == "" || req.VendorURL == "" {
		return fiber.NewError(fiber.StatusBadRequest, "cookie_name and vendor_url required")
	}
	secure := true
	if req.Secure != nil {
		secure = *req.Secure
	}
	httpOnly := false
	if req.HTTPOnly != nil {
		httpOnly = *req.HTTPOnly
	}
	ce := &domain.CookieExtension{
		ServiceID:    sid,
		CookieName:   req.CookieName,
		VendorURL:    req.VendorURL,
		NewLifetimeS: req.NewLifetimeS,
		CookieDomain: req.CookieDomain,
		Path:         req.Path,
		Secure:       secure,
		HTTPOnly:     httpOnly,
		SameSite:     req.SameSite,
		IsActive:     true,
	}
	if err := h.svc.Create(c.Context(), ce); err != nil {
		return fiber.NewError(fiber.StatusUnprocessableEntity, err.Error())
	}
	return c.Status(201).JSON(ce)
}

type updateCookieExtReq struct {
	VendorURL    string  `json:"vendor_url"`
	NewLifetimeS int     `json:"new_lifetime_s"`
	CookieDomain *string `json:"cookie_domain,omitempty"`
	Path         string  `json:"path"`
	Secure       *bool   `json:"secure"`
	HTTPOnly     *bool   `json:"http_only"`
	SameSite     string  `json:"same_site"`
	IsActive     *bool   `json:"is_active"`
}

func (h *CookieExtHandler) Update(c *fiber.Ctx) error {
	id, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid id")
	}
	var req updateCookieExtReq
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid body")
	}
	cur, err := h.svc.Get(c.Context(), id)
	if err != nil || cur == nil {
		return fiber.NewError(fiber.StatusNotFound, "cookie extension not found")
	}
	if req.VendorURL != "" {
		cur.VendorURL = req.VendorURL
	}
	if req.NewLifetimeS > 0 {
		cur.NewLifetimeS = req.NewLifetimeS
	}
	cur.CookieDomain = req.CookieDomain
	if req.Path != "" {
		cur.Path = req.Path
	}
	if req.Secure != nil {
		cur.Secure = *req.Secure
	}
	if req.HTTPOnly != nil {
		cur.HTTPOnly = *req.HTTPOnly
	}
	if req.SameSite != "" {
		cur.SameSite = req.SameSite
	}
	if req.IsActive != nil {
		cur.IsActive = *req.IsActive
	}
	if err := h.svc.Update(c.Context(), cur); err != nil {
		return err
	}
	return c.JSON(cur)
}

func (h *CookieExtHandler) Delete(c *fiber.Ctx) error {
	id, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid id")
	}
	actor := "admin"
	if cl := auth.MustClaims(c); cl != nil {
		actor = cl.Email
	}
	if err := h.svc.Delete(c.Context(), id, actor); err != nil {
		return err
	}
	return c.JSON(fiber.Map{"ok": true})
}

func (h *CookieExtHandler) Test(c *fiber.Ctx) error {
	id, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid id")
	}
	res, err := h.svc.Test(c.Context(), id)
	if err != nil {
		return fiber.NewError(fiber.StatusUnprocessableEntity, err.Error())
	}
	return c.JSON(res)
}

func (h *CookieExtHandler) Analytics(c *fiber.Ctx) error {
	id, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid id")
	}
	ce, err := h.svc.Get(c.Context(), id)
	if err != nil || ce == nil {
		return fiber.NewError(fiber.StatusNotFound, "cookie extension not found")
	}
	return c.JSON(fiber.Map{
		"cookie":      ce.CookieName,
		"hit_count":   ce.HitCount,
		"last_used":   ce.LastUsedAt,
		"is_active":   ce.IsActive,
		"lifetime_s":  ce.NewLifetimeS,
	})
}

func (h *CookieExtHandler) Logs(c *fiber.Ctx) error {
	sid, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid service id")
	}
	limit := 100
	if s := c.Query("limit"); s != "" {
		if n, err := strconv.Atoi(s); err == nil {
			limit = n
		}
	}
	logs, err := h.svc.RecentLogs(c.Context(), sid, limit)
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{"items": logs})
}