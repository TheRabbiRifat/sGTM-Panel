package heartbeat

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/rs/zerolog"

	"github.com/hostaffin/sgtm/node-agent/internal/config"
)

// Heartbeat is the periodic liveness pinger.
type Heartbeat struct {
	cfg      *config.Config
	hc       *http.Client
	logger   zerolog.Logger
}

// New constructs a heartbeat.
func New(cfg *config.Config, hc *http.Client, logger zerolog.Logger) *Heartbeat {
	return &Heartbeat{cfg: cfg, hc: hc, logger: logger}
}

// Loop runs until ctx is cancelled.
func (h *Heartbeat) Loop(ctx context.Context) {
	t := time.NewTicker(h.cfg.HeartbeatEvery)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			if err := h.send(ctx); err != nil {
				h.logger.Warn().Err(err).Msg("heartbeat failed")
			}
		}
	}
}

type payload struct {
	NodeID      string    `json:"node_id"`
	Time        time.Time `json:"time"`
	AgentVersion string   `json:"agent_version"`
}

func (h *Heartbeat) send(ctx context.Context) error {
	body, _ := json.Marshal(payload{
		NodeID:      h.cfg.NodeID,
		Time:        time.Now().UTC(),
		AgentVersion: "0.1.0",
	})
	url := h.cfg.ControlPlaneURL + "/internal/heartbeat"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Node-Id", h.cfg.NodeID)
	req.Header.Set("X-Node-Api-Key", h.cfg.NodeAPIKey)
	resp, err := h.hc.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		h.logger.Warn().Int("status", resp.StatusCode).Msg("heartbeat non-2xx")
	}
	return nil
}