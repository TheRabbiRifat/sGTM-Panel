package auth

import (
	"crypto/rsa"
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Claims is the JWT body for both access and refresh tokens.
type Claims struct {
	UserID    string   `json:"sub"`
	Email     string   `json:"email"`
	Role      string   `json:"role"`
	Type      string   `json:"typ"` // "access" or "refresh"
	WhmcsCID  int      `json:"whmcs_cid,omitempty"`
	Scopes    []string `json:"scopes,omitempty"`
	jwt.RegisteredClaims
}

// JWT issues and validates RS256 tokens.
type JWT struct {
	private *rsa.PrivateKey
	public  *rsa.PublicKey
	access  time.Duration
	refresh time.Duration
}

// NewJWT constructs a manager from PEM-encoded keys.
func NewJWT(privPEM, pubPEM string, access, refresh time.Duration) *JWT {
	var j = &JWT{access: access, refresh: refresh}
	if privPEM != "" {
		priv, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(privPEM))
		if err == nil {
			j.private = priv
		}
	}
	if pubPEM != "" {
		pub, err := jwt.ParseRSAPublicKeyFromPEM([]byte(pubPEM))
		if err == nil {
			j.public = pub
		}
	}
	return j
}

// Sign generates a token of the given type ("access" or "refresh").
func (j *JWT) Sign(userID, email, role string, whmcsCID int, kind string) (string, error) {
	if j.private == nil {
		return "", errors.New("jwt private key not configured")
	}
	ttl := j.access
	if kind == "refresh" {
		ttl = j.refresh
	}
	c := Claims{
		UserID: userID,
		Email:  email,
		Role:   role,
		Type:   kind,
		WhmcsCID: whmcsCID,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    "hostaffin-sgtm",
			Audience:  jwt.ClaimStrings{"hostaffin-sgtm-api"},
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(ttl)),
			ID:        fmt.Sprintf("%d", time.Now().UnixNano()),
		},
	}
	tok := jwt.NewWithClaims(jwt.SigningMethodRS256, c)
	return tok.SignedString(j.private)
}

// Verify parses and validates a token.
func (j *JWT) Verify(tokenStr string) (*Claims, error) {
	if j.public == nil {
		return nil, errors.New("jwt public key not configured")
	}
	parsed, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(t *jwt.Token) (interface{}, error) {
		if _, ok := t.Method.(*jwt.SigningMethodRSA); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return j.public, nil
	})
	if err != nil {
		return nil, err
	}
	c, ok := parsed.Claims.(*Claims)
	if !ok || !parsed.Valid {
		return nil, errors.New("invalid token")
	}
	return c, nil
}