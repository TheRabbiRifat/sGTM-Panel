package auth

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"fmt"
	"strings"

	"golang.org/x/crypto/argon2"
)

type argonParams struct {
	memory  uint32
	iter    uint32
	threads uint8
	saltLen uint32
	keyLen  uint32
}

var defaultArgon = argonParams{
	memory:  64 * 1024,
	iter:    3,
	threads: 2,
	saltLen: 16,
	keyLen:  32,
}

// HashPassword returns a PHC-formatted argon2id string.
func HashPassword(pwd string) (string, error) {
	p := defaultArgon
	salt := make([]byte, p.saltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", err
	}
	key := argon2.IDKey([]byte(pwd), salt, p.iter, p.memory, p.threads, p.keyLen)
	return fmt.Sprintf("$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version, p.memory, p.iter, p.threads,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(key),
	), nil
}

// VerifyPassword checks a PHC-formatted argon2id string against a plain password.
func VerifyPassword(pwd, encoded string) (bool, error) {
	parts := strings.Split(encoded, "$")
	if len(parts) != 6 {
		return false, errors.New("invalid encoded hash format")
	}
	if parts[1] != "argon2id" {
		return false, errors.New("unsupported algorithm: " + parts[1])
	}
	var version int
	if _, err := fmt.Sscanf(parts[2], "v=%d", &version); err != nil {
		return false, err
	}
	var m, t uint32
	var p uint8
	if _, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &m, &t, &p); err != nil {
		return false, err
	}
	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return false, err
	}
	want, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil {
		return false, err
	}
	got := argon2.IDKey([]byte(pwd), salt, t, m, p, uint32(len(want)))
	return subtle.ConstantTimeCompare(want, got) == 1, nil
}

// RandomToken returns a base64url-encoded random token of n bytes.
func RandomToken(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}