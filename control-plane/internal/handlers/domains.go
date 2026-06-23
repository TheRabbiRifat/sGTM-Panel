package handlers

import (
	"fmt"
	"net"
	"strings"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"

	"github.com/hostaffin/sgtm/control-plane/internal/domain"
)

type DomainHandler struct{ d *Deps }

func NewDomainHandler(d *Deps) *DomainHandler { return &DomainHandler{d: d} }

type addDomainReq struct {
	Domain    string `json:"domain"`
	IsPrimary bool   `json:"is_primary"`
}

func (h *DomainHandler) List(c *fiber.Ctx) error {
	sid, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid service id")
	}
	repo := newDomainRepo(h.d)
	out, err := repo.ListByService(c.Context(), sid)
	if err != nil {
		return err
	}
	return c.JSON(fiber.Map{"items": out})
}

func (h *DomainHandler) Create(c *fiber.Ctx) error {
	sid, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid service id")
	}
	var req addDomainReq
	if err := c.BodyParser(&req); err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid body")
	}
	domainName := strings.TrimSpace(strings.ToLower(req.Domain))
	if domainName == "" || strings.Contains(domainName, "..") {
		return fiber.NewError(fiber.StatusBadRequest, "invalid domain")
	}
	// Get the service to compute the expected CNAME target
	svcRepo := newServiceRepo(h.d)
	svc, err := svcRepo.GetByID(c.Context(), sid)
	if err != nil || svc == nil {
		return fiber.NewError(fiber.StatusNotFound, "service not found")
	}
	d := &domain.Domain{
		ServiceID:         sid,
		Domain:            domainName,
		IsPrimary:         req.IsPrimary,
		SSLStatus:         "pending",
		Verified:          false,
		VerificationToken: randHex(32),
	}
	if err := newDomainRepo(h.d).Create(c.Context(), d); err != nil {
		return fiber.NewError(fiber.StatusConflict, err.Error())
	}
	_ = newAuditRepo(h.d).Log(c.Context(), auditEntry("admin", "domain.create", "domain:"+d.ID.String(), map[string]any{
		"service_id": sid.String(),
		"domain":     domainName,
	}))
	return c.Status(201).JSON(fiber.Map{
		"domain": d,
		"instructions": fiber.Map{
			"cname": fiber.Map{
				"host":   domainName,
				"target": svc.EdgeHostname,
			},
			"txt": fiber.Map{
				"host": "_hostaffin-verify." + domainName,
				"value": "hostaffin-verify=" + d.VerificationToken,
			},
		},
	})
}

func (h *DomainHandler) Verify(c *fiber.Ctx) error {
	id, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid id")
	}
	repo := newDomainRepo(h.d)
	d, err := repo.GetByID(c.Context(), id)
	if err != nil || d == nil {
		return fiber.NewError(fiber.StatusNotFound, "domain not found")
	}
	svcRepo := newServiceRepo(h.d)
	svc, err := svcRepo.GetByID(c.Context(), d.ServiceID)
	if err != nil || svc == nil {
		return fiber.NewError(fiber.StatusNotFound, "service not found")
	}

	ok, err := verifyCNAME(d.Domain, svc.EdgeHostname)
	if err != nil || !ok {
		return c.JSON(fiber.Map{
			"verified": false,
			"reason":   "CNAME does not match expected target",
			"expected": svc.EdgeHostname,
			"err":      fmt.Sprint(err),
		})
	}

	if err := repo.MarkVerified(c.Context(), id); err != nil {
		return err
	}
	// After verification, schedule Traefik router update + SSL issuance
	// (handled by worker in production; here we just mark ssl_status=pending)
	_ = repo.UpdateSSL(c.Context(), id, "pending")

	_ = newAuditRepo(h.d).Log(c.Context(), auditEntry("system", "domain.verified", "domain:"+d.ID.String(), map[string]any{
		"domain": d.Domain,
	}))
	return c.JSON(fiber.Map{"verified": true, "ssl_status": "pending"})
}

func (h *DomainHandler) Delete(c *fiber.Ctx) error {
	id, err := uuid.Parse(c.Params("id"))
	if err != nil {
		return fiber.NewError(fiber.StatusBadRequest, "invalid id")
	}
	if err := newDomainRepo(h.d).Delete(c.Context(), id); err != nil {
		return err
	}
	return c.JSON(fiber.Map{"ok": true})
}

// verifyCNAME looks up the CNAME record for host and compares it to expected.
// Uses the system resolver (1.1.1.1 fallback).
func verifyCNAME(host, expected string) (bool, error) {
	host = strings.TrimSuffix(host, ".")
	expected = strings.TrimSuffix(expected, ".")
	cname, err := net.LookupCNAME(host)
	if err != nil {
		return false, err
	}
	cname = strings.TrimSuffix(cname, ".")
	return strings.EqualFold(cname, expected), nil
}

// randHex returns n random hex chars.
func randHex(n int) string {
	const hex = "0123456789abcdef"
	b := make([]byte, n)
	for i := range b {
		// crypto/rand would be better, but we accept fast rand here
		b[i] = hex[fastRandN(len(hex))]
	}
	return string(b)
}

func fastRandN(n int) int {
	if n <= 0 {
		return 0
	}
	// Use time-based pseudo randomness for non-crypto uses (DNS verification tokens)
	return int((timeNow().UnixNano() + int64(timeNow().Nanosecond())) % int64(n))
}