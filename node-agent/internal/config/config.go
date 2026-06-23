package config

import (
	"strings"

	"github.com/spf13/viper"
)

// Config is the runtime configuration for the node-agent.
type Config struct {
	NodeID         string
	NodeAPIKey     string
	ControlPlaneURL string
	HeartbeatEvery time.Duration
	MetricsEvery   time.Duration
	DockerHost     string
}

// Load reads configuration from env / .env file.
func Load() *Config {
	v := viper.New()
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	v.AutomaticEnv()

	v.SetDefault("CONTROL_PLANE_URL", "http://localhost:8080")
	v.SetDefault("HEARTBEAT_EVERY", "30s")
	v.SetDefault("METRICS_EVERY", "15s")
	v.SetDefault("DOCKER_HOST", "unix:///var/run/docker.sock")

	return &Config{
		NodeID:          v.GetString("NODE_ID"),
		NodeAPIKey:      v.GetString("NODE_API_KEY"),
		ControlPlaneURL: v.GetString("CONTROL_PLANE_URL"),
		HeartbeatEvery:  v.GetDuration("HEARTBEAT_EVERY"),
		MetricsEvery:    v.GetDuration("METRICS_EVERY"),
		DockerHost:      v.GetString("DOCKER_HOST"),
	}
}