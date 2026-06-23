package observability

import (
	"os"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/rs/zerolog"
)

func NewLogger(level string) zerolog.Logger {
	zerolog.TimeFieldFormat = time.RFC3339Nano
	zerolog.MessageFieldName = "msg"
	zerolog.LevelFieldName = "level"

	lvl, err := zerolog.ParseLevel(level)
	if err != nil || lvl == zerolog.NoLevel {
		lvl = zerolog.InfoLevel
	}
	zerolog.SetGlobalLevel(lvl)

	return zerolog.New(os.Stdout).With().
		Timestamp().
		Str("svc", "control-plane").
		Logger()
}

// FiberLogger logs requests with structured fields.
func FiberLogger(log zerolog.Logger) fiber.Handler {
	return func(c *fiber.Ctx) error {
		start := time.Now()
		err := c.Next()
		latency := time.Since(start)

		rid, _ := c.Locals("requestid").(string)
		if rid == "" {
			rid = uuid.NewString()
			c.Locals("requestid", rid)
		}

		evt := log.Info()
		if err != nil {
			evt = log.Error().Err(err)
		}
		evt.
			Str("rid", rid).
			Str("ip", c.IP()).
			Str("method", c.Method()).
			Str("path", c.Path()).
			Int("status", c.Response().StatusCode()).
			Dur("latency", latency).
			Int("bytes", len(c.Response().Body())).
			Msg("http")
		return err
	}
}