package auth

import (
	"strings"

	"github.com/gofiber/fiber/v2"
)

// LocalsKey is the context key under which the JWT claims are stored.
const LocalsKey = "auth_claims"

// Middleware returns a Fiber middleware that validates a Bearer JWT.
func Middleware(j *JWT) fiber.Handler {
	return func(c *fiber.Ctx) error {
		h := c.Get("Authorization")
		if h == "" || !strings.HasPrefix(strings.ToLower(h), "bearer ") {
			return fiber.NewError(fiber.StatusUnauthorized, "missing bearer token")
		}
		tok := strings.TrimSpace(h[len("Bearer "):])
		claims, err := j.Verify(tok)
		if err != nil {
			return fiber.NewError(fiber.StatusUnauthorized, "invalid token: "+err.Error())
		}
		if claims.Type != "access" {
			return fiber.NewError(fiber.StatusUnauthorized, "wrong token type")
		}
		c.Locals(LocalsKey, claims)
		return c.Next()
	}
}

// RequireRoles allows only the given roles.
func RequireRoles(roles ...string) fiber.Handler {
	allowed := make(map[string]struct{}, len(roles))
	for _, r := range roles {
		allowed[r] = struct{}{}
	}
	return func(c *fiber.Ctx) error {
		cl := MustClaims(c)
		if _, ok := allowed[cl.Role]; !ok {
			return fiber.NewError(fiber.StatusForbidden, "insufficient role")
		}
		return c.Next()
	}
}

// MustClaims returns the JWT claims set on the request context.
func MustClaims(c *fiber.Ctx) *Claims {
	v, _ := c.Locals(LocalsKey).(*Claims)
	return v
}