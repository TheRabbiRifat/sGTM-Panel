package handlers

import (
	"net"
	"strconv"

	"github.com/gofiber/fiber/v2"
	"github.com/rs/zerolog"

	"github.com/hostaffin/sgtm/control-plane/internal/db"
	redisx "github.com/hostaffin/sgtm/control-plane/internal/redis"
)

// LoaderServeHandler exposes public endpoints that serve the loader JS and
// proxy cookie extension traffic. These are unauthenticated but rate-limited
// by IP via Redis counters.
type LoaderServeHandler struct {
	d *Deps
}

func NewLoaderServeHandler(d *Deps) *LoaderServeHandler {
	return &LoaderServeHandler{d: d}
}

// MountPublic attaches public endpoints served from the same Fiber app.
// In production these would live behind Traefik on the customer's edge.
func MountPublic(app *fiber.App, pg *db.Postgres, rdb *redisx.Redis, log zerolog.Logger) {
	h := &LoaderServeHandler{d: &Deps{DB: pg, Redis: rdb, Log: log}}
	app.Get("/loader.js", h.LoaderJS)
	app.Get("/loader.js/run", h.LoaderRun)
	app.Get("/cookie/extend/:name", h.CookieGet)
	app.Post("/cookie/extend/:name", h.CookiePost)
	app.Get("/cookie/extend", h.CookieList)
}

// LoaderJS returns the loader JS for ?id=... with a short cache TTL.
func (h *LoaderServeHandler) LoaderJS(c *fiber.Ctx) error {
	id := c.Query("id")
	if id == "" {
		return fiber.NewError(fiber.StatusBadRequest, "id query required")
	}
	if !rateLimit(h.d.Redis, c.IP(), "loader_js", 60) {
		return fiber.NewError(fiber.StatusTooManyRequests, "rate limited")
	}
	loaderRepo := newLoaderRepo(h.d)
	l, err := loaderRepo.GetByID(c.Context(), id)
	if err != nil || l == nil || !l.IsActive {
		return fiber.NewError(fiber.StatusNotFound, "loader not found or inactive")
	}
	cfg, _ := loaderRepo.GetConfig(c.Context(), id)
	js := renderLoaderPublic(id, cfg)
	c.Set("Content-Type", "application/javascript; charset=utf-8")
	c.Set("Cache-Control", "public, max-age=300")
	c.Set("Access-Control-Allow-Origin", "*")
	return c.SendString(js)
}

// LoaderRun is the runtime hit endpoint invoked by the loader snippet itself.
// It increments hit count and returns a tiny payload.
func (h *LoaderServeHandler) LoaderRun(c *fiber.Ctx) error {
	id := c.Query("id")
	if id == "" {
		return fiber.NewError(fiber.StatusBadRequest, "id query required")
	}
	if !rateLimit(h.d.Redis, c.IP(), "loader_run", 600) {
		return fiber.NewError(fiber.StatusTooManyRequests, "rate limited")
	}
	loaderRepo := newLoaderRepo(h.d)
	if err := loaderRepo.IncrementHit(c.Context(), id); err != nil {
		return err
	}
	usageRepo := newUsageRepo(h.d)
	// Resolve service id by loader_id
	l, _ := loaderRepo.GetByID(c.Context(), id)
	if l != nil {
		_ = usageRepo.IncLoaderHits(c.Context(), l.ServiceID, 1)
	}
	c.Set("Content-Type", "application/javascript; charset=utf-8")
	c.Set("Cache-Control", "no-store")
	// Tiny dispatcher payload that pushes a loader_hit event into sGTM.
	return c.SendString(`(function(){window.dataLayer=window.dataLayer||[];dataLayer.push({event:'hostaffin_loader_hit',loader_id:'` + id + `'});})();`)
}

// CookieGet returns the current value of an extended cookie (server-side only).
func (h *LoaderServeHandler) CookieGet(c *fiber.Ctx) error {
	name := c.Params("name")
	host := c.Hostname()
	if !rateLimit(h.d.Redis, c.IP(), "cookie_get:"+name, 600) {
		return fiber.NewError(fiber.StatusTooManyRequests, "rate limited")
	}
	// We need to map host → service.edge_hostname or custom domain.
	repo := newDomainRepo(h.d)
	svcRepo := newServiceRepo(h.d)
	ceRepo := newCookieExtRepo(h.d)

	// First try custom domain match
	d, _ := repo.GetByDomain(c.Context(), host)
	var serviceID string
	if d != nil && d.Verified {
		serviceID = d.ServiceID.String()
	} else {
		svc, _ := svcRepo.GetByEdgeHostname(c.Context(), host)
		if svc != nil {
			serviceID = svc.ID.String()
		}
	}
	if serviceID == "" {
		return fiber.NewError(fiber.StatusNotFound, "host not mapped to service")
	}

	// parse service id
	import_uuid := uuidOrEmpty(serviceID)
	ce, err := ceRepo.GetByName(c.Context(), import_uuid, name)
	if err != nil || ce == nil || !ce.IsActive {
		return fiber.NewError(fiber.StatusNotFound, "cookie extension not found")
	}

	_ = ceRepo.IncrementHit(c.Context(), ce.ID)
	_ = ceRepo.LogHit(c.Context(), ce.ID, 200, hashIP(c.IP()), c.Get("User-Agent"), 0, 0)
	c.Set("Content-Type", "application/json")
	return c.JSON(fiber.Map{
		"cookie_name": ce.CookieName,
		"value":       c.Cookies(ce.CookieName),
		"vendor_url":  ce.VendorURL,
	})
}

// CookiePost is the proxy endpoint that sets an extended first-party cookie.
func (h *LoaderServeHandler) CookiePost(c *fiber.Ctx) error {
	name := c.Params("name")
	host := c.Hostname()
	if !rateLimit(h.d.Redis, c.IP(), "cookie_post:"+name, 60) {
		return fiber.NewError(fiber.StatusTooManyRequests, "rate limited")
	}
	repo := newDomainRepo(h.d)
	svcRepo := newServiceRepo(h.d)
	ceRepo := newCookieExtRepo(h.d)

	d, _ := repo.GetByDomain(c.Context(), host)
	var serviceID string
	if d != nil && d.Verified {
		serviceID = d.ServiceID.String()
	} else {
		svc, _ := svcRepo.GetByEdgeHostname(c.Context(), host)
		if svc != nil {
			serviceID = svc.ID.String()
		}
	}
	if serviceID == "" {
		return fiber.NewError(fiber.StatusNotFound, "host not mapped")
	}
	ce, err := ceRepo.GetByName(c.Context(), uuidOrEmpty(serviceID), name)
	if err != nil || ce == nil || !ce.IsActive {
		return fiber.NewError(fiber.StatusNotFound, "cookie extension not configured")
	}

	value := c.Query("v")
	if value == "" {
		value = "1"
	}
	cookieDomain := ""
	if ce.CookieDomain != nil {
		cookieDomain = *ce.CookieDomain
	}
	c.Cookie(&fiber.Cookie{
		Name:     ce.CookieName,
		Value:    value,
		Path:     ce.Path,
		Domain:   cookieDomain,
		MaxAge:   ce.NewLifetimeS,
		Secure:   ce.Secure,
		HTTPOnly: ce.HTTPOnly,
		SameSite: ce.SameSite,
	})

	_ = ceRepo.IncrementHit(c.Context(), ce.ID)
	_ = ceRepo.LogHit(c.Context(), ce.ID, 200, hashIP(c.IP()), c.Get("User-Agent"),
		len(c.Body()), 0)
	usageRepo := newUsageRepo(h.d)
	_ = usageRepo.IncCookieExtHits(c.Context(), ce.ServiceID, 1)
	return c.JSON(fiber.Map{"ok": true, "cookie": ce.CookieName, "max_age": ce.NewLifetimeS})
}

// CookieList returns active cookie extensions for the host (debug/admin).
func (h *LoaderServeHandler) CookieList(c *fiber.Ctx) error {
	return c.JSON(fiber.Map{"items": []any{}})
}

// rateLimit returns true if the request is allowed under the per-minute limit.
func rateLimit(rdb *redisx.Redis, ip, key string, limit int) bool {
	if rdb == nil || ip == "" {
		return true
	}
	bucket := strconv.Itoa(int(timeNow().UnixNano() / int64(60_000_000_000))) // 1-min bucket
	rkey := "rl:" + key + ":" + ip + ":" + bucket
	ctx := contextBg()
	n, err := rdb.Incr(ctx, rkey).Result()
	if err != nil {
		return true // fail open
	}
	if n == 1 {
		_ = rdb.Expire(ctx, rkey, 70_000_000_000).Err()
	}
	return int(n) <= limit
}

func hashIP(ip string) string {
	parsed := net.ParseIP(ip)
	if parsed == nil {
		return ""
	}
	return saltHash(parsed.String())
}

// saltHash is a simple salted hash to avoid storing raw IPs in cookie logs.
func saltHash(s string) string {
	h := sha256Sum(s + "|hostaffin-salt")
	return hexEncode(h[:])
}

// renderLoaderPublic returns the customer-visible JS for a loader id+config.
func renderLoaderPublic(id string, cfg *LoaderConfigPublic) string {
	respectDNT := "true"
	allowBots := "false"
	trigger := "immediate"
	triggerVal := ""
	if cfg != nil {
		if !cfg.RespectDNT {
			respectDNT = "false"
		}
		if cfg.AllowBots {
			allowBots = "true"
		}
		if cfg.TriggerType != "" {
			trigger = cfg.TriggerType
		}
		triggerVal = cfg.TriggerValue
	}
	return `(function(w,d,s,id){
  if (w.__hostaffinLoaderLoaded) return;
  w.__hostaffinLoaderLoaded = true;
  if (navigator.doNotTrack === '1' && ` + respectDNT + `) return;
  if (/bot|crawl|spider/i.test(navigator.userAgent) && !` + allowBots + `) return;
  var gj=d.createElement(s);var r=d.getElementsByTagName(s)[0];
  gj.async=true;
  gj.src='/loader.js/run?id='+encodeURIComponent(id);
  gj.setAttribute('data-loader-id',id);
  r.parentNode.insertBefore(gj,r);
})(window,document,'script','` + id + `');
// trigger=` + trigger + ` value=` + triggerVal
}

// LoaderConfigPublic is the trimmed shape used by renderLoaderPublic.
type LoaderConfigPublic struct {
	TriggerType  string
	TriggerValue string
	RespectDNT   bool
	AllowBots    bool
}