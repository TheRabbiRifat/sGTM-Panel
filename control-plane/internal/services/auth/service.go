package authsvc

import (
	"context"
	"errors"

	"github.com/hostaffin/sgtm/control-plane/internal/auth"
	"github.com/hostaffin/sgtm/control-plane/internal/repos"
)

// Service handles admin login / refresh.
type Service struct {
	users *repos.UserRepo
	jwt   *auth.JWT
}

func New(users *repos.UserRepo, jwt *auth.JWT) *Service {
	return &Service{users: users, jwt: jwt}
}

type LoginResult struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	UserID       string `json:"user_id"`
	Email        string `json:"email"`
	Role         string `json:"role"`
}

func (s *Service) Login(ctx context.Context, email, password string) (*LoginResult, error) {
	u, err := s.users.GetByEmail(ctx, email)
	if err != nil {
		return nil, err
	}
	if u == nil || !u.IsActive {
		return nil, errors.New("invalid credentials")
	}
	ok, err := auth.VerifyPassword(password, u.Password)
	if err != nil {
		return nil, err
	}
	if !ok {
		return nil, errors.New("invalid credentials")
	}
	access, err := s.jwt.Sign(u.ID.String(), u.Email, string(u.Role), 0, "access")
	if err != nil {
		return nil, err
	}
	refresh, err := s.jwt.Sign(u.ID.String(), u.Email, string(u.Role), 0, "refresh")
	if err != nil {
		return nil, err
	}
	_ = s.users.UpdateLastLogin(ctx, u.ID)
	return &LoginResult{
		AccessToken:  access,
		RefreshToken: refresh,
		UserID:       u.ID.String(),
		Email:        u.Email,
		Role:         string(u.Role),
	}, nil
}

func (s *Service) Refresh(ctx context.Context, refreshToken string) (*LoginResult, error) {
	claims, err := s.jwt.Verify(refreshToken)
	if err != nil || claims.Type != "refresh" {
		return nil, errors.New("invalid refresh token")
	}
	u, err := s.users.GetByEmail(ctx, claims.Email)
	if err != nil || u == nil || !u.IsActive {
		return nil, errors.New("user not found")
	}
	access, err := s.jwt.Sign(u.ID.String(), u.Email, string(u.Role), 0, "access")
	if err != nil {
		return nil, err
	}
	newRefresh, err := s.jwt.Sign(u.ID.String(), u.Email, string(u.Role), 0, "refresh")
	if err != nil {
		return nil, err
	}
	return &LoginResult{
		AccessToken:  access,
		RefreshToken: newRefresh,
		UserID:       u.ID.String(),
		Email:        u.Email,
		Role:         string(u.Role),
	}, nil
}