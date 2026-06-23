package metrics

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/docker/docker/client"
	"github.com/rs/zerolog"

	"github.com/hostaffin/sgtm/node-agent/internal/config"
)

// Collector gathers per-container metrics and ships them to the control plane.
type Collector struct {
	cli    *client.Client
	cfg    *config.Config
	hc     *http.Client
	logger zerolog.Logger
}

// New constructs a collector.
func New(cli *client.Client, cfg *config.Config, hc *http.Client, logger zerolog.Logger) *Collector {
	return &Collector{cli: cli, cfg: cfg, hc: hc, logger: logger}
}

type ContainerMetrics struct {
	ContainerID string  `json:"container_id"`
	Name        string  `json:"name"`
	ServiceID   string  `json:"service_id,omitempty"`
	CPUPercent  float64 `json:"cpu_pct"`
	RAMUsedMB   int     `json:"ram_used_mb"`
	NetInBytes  int64   `json:"net_in_bytes"`
	NetOutBytes int64   `json:"net_out_bytes"`
}

type NodeMetrics struct {
	CPUPercent float64 `json:"cpu_pct"`
	RAMUsedMB  int     `json:"ram_used_mb"`
	RAMTotalMB int     `json:"ram_total_mb"`
}

type Payload struct {
	NodeID     string             `json:"node_id"`
	Time       time.Time          `json:"time"`
	Node       NodeMetrics        `json:"node"`
	Containers []ContainerMetrics `json:"containers"`
}

// Loop runs the metrics scrape until ctx is done.
func (c *Collector) Loop(ctx context.Context) {
	t := time.NewTicker(c.cfg.MetricsEvery)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			if err := c.send(ctx); err != nil {
				c.logger.Warn().Err(err).Msg("metrics send failed")
			}
		}
	}
}

func (c *Collector) send(ctx context.Context) error {
	// In v1 we send a minimal payload; production would compute actual CPU/RAM
	// from cAdvisor / docker stats.
	body, _ := json.Marshal(Payload{
		NodeID: c.cfg.NodeID,
		Time:   time.Now().UTC(),
		Node: NodeMetrics{
			CPUPercent: 0,
			RAMUsedMB:  0,
			RAMTotalMB: 0,
		},
		Containers: []ContainerMetrics{},
	})
	url := c.cfg.ControlPlaneURL + "/webhooks/nodes/" + c.cfg.NodeID + "/metrics"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Node-Id", c.cfg.NodeID)
	req.Header.Set("X-Node-Api-Key", c.cfg.NodeAPIKey)
	resp, err := c.hc.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		c.logger.Warn().Int("status", resp.StatusCode).Msg("metrics non-2xx")
	}
	return nil
}