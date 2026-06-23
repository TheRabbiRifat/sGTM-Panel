// Package main is the hostaffin-node-agent daemon.
//
// Responsibilities:
//   - Receive commands from the Control Plane (deploy, restart, delete)
//   - Run them against the local Docker daemon (Swarm-aware)
//   - Report heartbeats + per-container metrics
//   - Authenticate with the Control Plane using a per-node API key
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/docker/docker/client"
	"github.com/rs/zerolog"

	"github.com/hostaffin/sgtm/node-agent/internal/config"
	"github.com/hostaffin/sgtm/node-agent/internal/commands"
	"github.com/hostaffin/sgtm/node-agent/internal/heartbeat"
	"github.com/hostaffin/sgtm/node-agent/internal/metrics"
)

func main() {
	cfg := config.Load()
	logger := zerolog.New(os.Stdout).With().Timestamp().Str("svc", "node-agent").Logger()
	logger.Info().Str("node_id", cfg.NodeID).Msg("starting")

	// Docker client (talks to local daemon via /var/run/docker.sock)
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		logger.Fatal().Err(err).Msg("docker client")
	}
	defer cli.Close()

	// HTTP server for inbound commands (control-plane callbacks).
	httpClient := &http.Client{Timeout: 30 * time.Second}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Heartbeat loop
	hb := heartbeat.New(cfg, httpClient, logger)
	go hb.Loop(ctx)

	// Metrics loop
	mc := metrics.New(cli, cfg, httpClient, logger)
	go mc.Loop(ctx)

	// Signal handling
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, os.Interrupt, syscall.SIGTERM)
	<-sigCh
	logger.Info().Msg("shutting down")
	cancel()
	time.Sleep(2 * time.Second)
}

// postJSON is a small helper for posting JSON to the control plane.
func postJSON(ctx context.Context, url string, body any, apiKey string) error {
	buf, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(buf))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-Node-Id", getEnvOr("NODE_ID", ""))
	req.Header.Set("X-Node-Api-Key", apiKey)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("control plane responded %d", resp.StatusCode)
	}
	return nil
}

func getEnvOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

// ensure commands package is referenced even if unused at build time.
var _ = commands.DeployResult{}