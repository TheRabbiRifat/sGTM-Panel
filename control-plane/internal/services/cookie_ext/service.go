package cookieext

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/rs/zerolog"

	"github.com/hostaffin/sgtm/control-plane/internal/domain"
	"github.com/hostaffin/sgtm/control-plane/internal/repos"
)

const chromeLifetimeCap = 34190000 // 395 days

// Service manages Cookie Extensions.
type Service struct {
	repo  *repos.CookieExtRepo
	audit *repos.AuditRepo
	log   zerolog.Logger
}

func New(repo *repos.CookieExtRepo, audit *repos.AuditRepo, log zerolog.Logger) *Service {
	return &Service{repo: repo, audit: audit, log: log}
}

// Create adds a new cookie extension to a service.
func (s *Service) Create(ctx context.Context, c *domain.CookieExtension) error {
	if c.CookieName == "" || c.VendorURL == "" {
		return errors.New("cookie_name and vendor_url are required")
	}
	if c.NewLifetimeS <= 0 {
		return errors.New("new_lifetime_s must be positive")
	}
	if c.NewLifetimeS > chromeLifetimeCap {
		c.NewLifetimeS = chromeLifetimeCap
	}
	if c.Path == "" {
		c.Path = "/"
	}
	if c.SameSite == "" {
		c.SameSite = "Lax"
	}
	if err := s.repo.Create(ctx, c); err != nil {
		return err
	}
	_ = s.audit.Log(ctx, repos.AuditEntry{
		ActorType: "admin", Action: "cookie_ext.create",
		Resource: "cookie_ext:" + c.ID.String(),
		Metadata: map[string]any{"service_id": c.ServiceID.String(), "cookie": c.CookieName},
	})
	return nil
}

// Update modifies an existing cookie extension.
func (s *Service) Update(ctx context.Context, c *domain.CookieExtension) error {
	return s.repo.Update(ctx, c)
}

// Delete removes a cookie extension.
func (s *Service) Delete(ctx context.Context, id uuid.UUID, actor string) error {
	if err := s.repo.Delete(ctx, id); err != nil {
		return err
	}
	_ = s.audit.Log(ctx, repos.AuditEntry{
		ActorType: actor, Action: "cookie_ext.delete", Resource: "cookie_ext:" + id.String(),
	})
	return nil
}

// List returns cookie extensions for a service.
func (s *Service) List(ctx context.Context, serviceID uuid.UUID) ([]domain.CookieExtension, error) {
	return s.repo.ListByService(ctx, serviceID)
}

// Get returns a single extension.
func (s *Service) Get(ctx context.Context, id uuid.UUID) (*domain.CookieExtension, error) {
	return s.repo.GetByID(ctx, id)
}

// RecentLogs returns recent request logs.
func (s *Service) RecentLogs(ctx context.Context, serviceID uuid.UUID, limit int) ([]repos.CookieExtLog, error) {
	return s.repo.RecentLogs(ctx, serviceID, limit)
}

// Test issues a synthetic request and returns the response that would be sent.
// The actual cookie is NOT set in any browser — this is server-to-server only.
func (s *Service) Test(ctx context.Context, id uuid.UUID) (map[string]any, error) {
	ext, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	if ext == nil {
		return nil, errors.New("cookie extension not found")
	}
	setCookie := buildSetCookieHeader(ext)
	return map[string]any{
		"set_cookie": setCookie,
		"vendor_url": ext.VendorURL,
		"lifetime_s": ext.NewLifetimeS,
		"would_redirect_to": "https://example.com/?ref=hostaffin-test",
		"note": "Synthetic test — no cookie was actually set in your browser.",
	}, nil
}

// buildSetCookieHeader assembles a Set-Cookie value from a config.
func buildSetCookieHeader(c *domain.CookieExtension) string {
	domain := ""
	if c.CookieDomain != nil && *c.CookieDomain != "" {
		domain = fmt.Sprintf(" Domain=%s;", *c.CookieDomain)
	}
	secure := ""
	if c.Secure {
		secure = " Secure;"
	}
	httpOnly := ""
	if c.HTTPOnly {
		httpOnly = " HttpOnly;"
	}
	sameSite := fmt.Sprintf(" SameSite=%s;", c.SameSite)
	maxAge := fmt.Sprintf(" Max-Age=%d;", c.NewLifetimeS)
	path := fmt.Sprintf(" Path=%s;", c.Path)
	return fmt.Sprintf("%s=test-value;%s%s%s%s%s%s", c.CookieName, path, maxAge, domain, secure, httpOnly, sameSite)
}

// PurgeOldLogs purges cookie extension logs older than the given duration.
func (s *Service) PurgeOldLogs(ctx context.Context, olderThan time.Duration) (int64, error) {
	return s.repo.PurgeOldLogs(ctx, olderThan)
}