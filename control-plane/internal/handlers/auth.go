package handlers

import (
	"github.com/gofiber/fiber/v2"

	authsvc "github.com/hostaffin/sgtm/control-plane/internal/services/auth"
)

type AuthHandler struct {
	d   *Deps
	svc *authsvc.Service
}

func NewAuthHandler(d *Deps) *AuthHandler {
	return &AuthHandler{d: d, svc: authsvc.New(
		newUserRepo(d), d.JWT,
	)}
}

func (h *AuthHandler) Login(c *fiber.Ctx) error {
	var req struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid body")
	}
	if req.Email == "" || req.Password == "" {
		return fiber.NewError(fiber.StatusBadRequest, "email and password required")
	}
	res, err := h.svc.Login(c.Context(), req.Email, req.Password)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, err.Error())
	}
	return c.JSON(res)
}

func (h *AuthHandler) Refresh(c *fiber.Ctx) error {
	var req struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := c.BodyParser(&req); err != nil || req.RefreshToken == "" {
		return fiber.NewError(fiber.StatusBadRequest, "refresh_token required")
	}
	res, err := h.svc.Refresh(c.Context(), req.RefreshToken)
	if err != nil {
		return fiber.NewError(fiber.StatusUnauthorized, err.Error())
	}
	return c.JSON(res)
}