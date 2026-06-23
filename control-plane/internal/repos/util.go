package repos

import (
	"crypto/rand"
	"encoding/hex"
)

// randomHex returns n random hex chars (2n random bytes).
func randomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return ""
	}
	return hex.EncodeToString(b)[:n]
}