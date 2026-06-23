package config

import (
	"fmt"
	"strings"
	"time"

	"github.com/spf13/viper"
)

// Config is the in-memory application configuration.
type Config struct {
	AppEnv    string
	AppName   string
	HTTPPort  int
	LogLevel  string
	BaseURL   string

	DatabaseURL string
	DBMaxOpen   int
	DBMaxIdle   int

	RedisURL string

	ClickHouseURL string
	ClickHouseDB  string

	JWTPrivateKeyPEM string
	JWTPublicKeyPEM  string
	JWTAccessTTL     time.Duration
	JWTRefreshTTL    time.Duration

	NodeAgentSharedSecret string

	WHMCSBaseURL        string
	WHMCSAPIIdentifier  string
	WHMCSAPISecret      string
	WHMCSWebhookSecret  string

	TraefikAPIURL string
	EdgeDomain    string

	SMTPHost string
	SMTPPort int
	SMTPUser string
	SMTPPass string
	SMTPFrom string

	TelegramBotToken string
	TelegramChatID   string
	DiscordWebhookURL string

	AdminBootstrapEmail    string
	AdminBootstrapPassword string
}

// Load reads configuration from environment / .env file.
func Load() *Config {
	v := viper.New()
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
	v.AutomaticEnv()

	v.SetDefault("APP_ENV", "development")
	v.SetDefault("APP_NAME", "hostaffin-sgtm")
	v.SetDefault("HTTP_PORT", 8080)
	v.SetDefault("LOG_LEVEL", "info")
	v.SetDefault("BASE_URL", "http://localhost:8080")

	v.SetDefault("DATABASE_URL", "postgres://sgtm:sgtm@localhost:5432/sgtm?sslmode=disable")
	v.SetDefault("DB_MAX_OPEN", 25)
	v.SetDefault("DB_MAX_IDLE", 5)

	v.SetDefault("REDIS_URL", "redis://localhost:6379/0")

	v.SetDefault("CLICKHOUSE_URL", "clickhouse://localhost:9000")
	v.SetDefault("CLICKHOUSE_DB", "sgtm")

	v.SetDefault("JWT_ACCESS_TTL", "15m")
	v.SetDefault("JWT_REFRESH_TTL", "168h")

	v.SetDefault("EDGE_DOMAIN", "edge.hostaffin.local")
	v.SetDefault("TRAEFIK_API_URL", "http://localhost:8081")

	return &Config{
		AppEnv:                  v.GetString("APP_ENV"),
		AppName:                 v.GetString("APP_NAME"),
		HTTPPort:                v.GetInt("HTTP_PORT"),
		LogLevel:                v.GetString("LOG_LEVEL"),
		BaseURL:                 v.GetString("BASE_URL"),
		DatabaseURL:             v.GetString("DATABASE_URL"),
		DBMaxOpen:               v.GetInt("DB_MAX_OPEN"),
		DBMaxIdle:               v.GetInt("DB_MAX_IDLE"),
		RedisURL:                v.GetString("REDIS_URL"),
		ClickHouseURL:           v.GetString("CLICKHOUSE_URL"),
		ClickHouseDB:            v.GetString("CLICKHOUSE_DB"),
		JWTPrivateKeyPEM:        v.GetString("JWT_PRIVATE_KEY_PEM"),
		JWTPublicKeyPEM:         v.GetString("JWT_PUBLIC_KEY_PEM"),
		JWTAccessTTL:            v.GetDuration("JWT_ACCESS_TTL"),
		JWTRefreshTTL:           v.GetDuration("JWT_REFRESH_TTL"),
		NodeAgentSharedSecret:   v.GetString("NODE_AGENT_SHARED_SECRET"),
		WHMCSBaseURL:            v.GetString("WHMCS_BASE_URL"),
		WHMCSAPIIdentifier:      v.GetString("WHMCS_API_IDENTIFIER"),
		WHMCSAPISecret:          v.GetString("WHMCS_API_SECRET"),
		WHMCSWebhookSecret:      v.GetString("WHMCS_WEBHOOK_SECRET"),
		TraefikAPIURL:           v.GetString("TRAEFIK_API_URL"),
		EdgeDomain:              v.GetString("EDGE_DOMAIN"),
		SMTPHost:                v.GetString("SMTP_HOST"),
		SMTPPort:                v.GetInt("SMTP_PORT"),
		SMTPUser:                v.GetString("SMTP_USER"),
		SMTPPass:                v.GetString("SMTP_PASS"),
		SMTPFrom:                v.GetString("SMTP_FROM"),
		TelegramBotToken:        v.GetString("TELEGRAM_BOT_TOKEN"),
		TelegramChatID:          v.GetString("TELEGRAM_CHAT_ID"),
		DiscordWebhookURL:       v.GetString("DISCORD_WEBHOOK_URL"),
		AdminBootstrapEmail:     v.GetString("ADMIN_BOOTSTRAP_EMAIL"),
		AdminBootstrapPassword:  v.GetString("ADMIN_BOOTSTRAP_PASSWORD"),
	}
}

// String returns a redacted, human-readable summary.
func (c *Config) String() string {
	return fmt.Sprintf("Config{env=%s port=%d db=%s redis=%s}",
		c.AppEnv, c.HTTPPort, redact(c.DatabaseURL), redact(c.RedisURL))
}

func redact(s string) string {
	if i := strings.Index(s, "@"); i > 0 {
		if j := strings.Index(s, "://"); j > 0 && j < i {
			return s[:j+3] + "***" + s[i:]
		}
	}
	return s
}