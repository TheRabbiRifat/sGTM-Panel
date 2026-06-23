package handlers

import (
	"context"
	"crypto/sha256"
	"encoding/hex"

	"github.com/google/uuid"
)

// contextBg returns a fresh background context (used for non-request Redis ops).
func contextBg() context.Context { return context.Background() }

// uuidOrEmpty parses s as a uuid; returns uuid.Nil on failure.
func uuidOrEmpty(s string) uuid.UUID {
	u, err := uuid.Parse(s)
	if err != nil {
		return uuid.Nil
	}
	return u
}

// sha256Sum returns sha256 of s.
func sha256Sum(s string) []byte {
	h := sha256.Sum256([]byte(s))
	return h[:]
}

// hexEncode encodes b as hex.
func hexEncode(b []byte) string { return hex.EncodeToString(b) }