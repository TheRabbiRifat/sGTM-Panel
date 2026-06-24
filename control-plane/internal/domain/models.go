package domain

import (
	"time"

	"github.com/google/uuid"
)

type Role string

const (
	RoleSuperAdmin Role = "super_admin"
	RoleAdmin      Role = "admin"
	RoleSupport    Role = "support"
)

type User struct {
	ID           uuid.UUID `db:"id" json:"id"`
	Email        string    `db:"email" json:"email"`
	Password     string    `db:"password" json:"-"`
	Role         Role      `db:"role" json:"role"`
	WhmcsClientID *int     `db:"whmcs_client_id" json:"whmcs_client_id,omitempty"`
	IsActive     bool      `db:"is_active" json:"is_active"`
	LastLoginAt  *time.Time `db:"last_login_at" json:"last_login_at,omitempty"`
	CreatedAt    time.Time  `db:"created_at" json:"created_at"`
	UpdatedAt    time.Time  `db:"updated_at" json:"updated_at"`
}

type Plan struct {
	ID                uuid.UUID `db:"id" json:"id"`
	WhmcsProductID    int       `db:"whmcs_product_id" json:"whmcs_product_id"`
	Name              string    `db:"name" json:"name"`
	Slug              string    `db:"slug" json:"slug"`
	CPULimit          float64   `db:"cpu_limit" json:"cpu_limit"`
	RAMLimitMB        int       `db:"ram_limit_mb" json:"ram_limit_mb"`
	RequestLimit      int64     `db:"request_limit" json:"request_limit"`
	BandwidthLimitGB  int       `db:"bandwidth_limit_gb" json:"bandwidth_limit_gb"`
	ContainerReplicas int       `db:"container_replicas" json:"container_replicas"`
	PriceCents        int       `db:"price_cents" json:"price_cents"`
	Currency          string    `db:"currency" json:"currency"`
	IsActive          bool      `db:"is_active" json:"is_active"`
}

type NodeStatus string

const (
	NodeOnline      NodeStatus = "online"
	NodeOffline     NodeStatus = "offline"
	NodeDraining    NodeStatus = "draining"
	NodeMaintenance NodeStatus = "maintenance"
	NodeDisabled    NodeStatus = "disabled"
)

// NodeRole identifies the role of a node in the cluster. Every node is a
// master node — there is no slave/non-edge role. The constant is retained
// for forward-compatibility but the only legal value is "master".
type NodeRole string

const (
	NodeRoleMaster NodeRole = "master"
)

type Node struct {
	ID             uuid.UUID  `db:"id" json:"id"`
	Hostname       string     `db:"hostname" json:"hostname"`
	Region         *string    `db:"region" json:"region,omitempty"`
	Status         NodeStatus `db:"status" json:"status"`
	TotalCPU       *float64   `db:"total_cpu" json:"total_cpu,omitempty"`
	TotalRAMMB     *int       `db:"total_ram_mb" json:"total_ram_mb,omitempty"`
	UsedCPU        float64    `db:"used_cpu" json:"used_cpu"`
	UsedRAMMB      int        `db:"used_ram_mb" json:"used_ram_mb"`
	ContainerCount int        `db:"container_count" json:"container_count"`
	LastHeartbeat  *time.Time `db:"last_heartbeat" json:"last_heartbeat,omitempty"`
	AgentVersion   *string    `db:"agent_version" json:"agent_version,omitempty"`
	Role           NodeRole   `db:"role" json:"role"`
	CreatedAt      time.Time  `db:"created_at" json:"created_at"`
}

type ServiceStatus string

const (
	ServicePending       ServiceStatus = "pending"
	ServiceProvisioning  ServiceStatus = "provisioning"
	ServiceActive        ServiceStatus = "active"
	ServiceSuspended     ServiceStatus = "suspended"
	ServiceTerminated    ServiceStatus = "terminated"
	ServiceFailed        ServiceStatus = "failed"
)

type Service struct {
	ID             uuid.UUID     `db:"id" json:"id"`
	WhmcsServiceID int           `db:"whmcs_service_id" json:"whmcs_service_id"`
	WhmcsClientID  int           `db:"whmcs_client_id" json:"whmcs_client_id"`
	PlanID         uuid.UUID     `db:"plan_id" json:"plan_id"`
	NodeID         *uuid.UUID    `db:"node_id" json:"node_id,omitempty"`
	ContainerID    *string       `db:"container_id" json:"container_id,omitempty"`
	ContainerName  *string       `db:"container_name" json:"container_name,omitempty"`
	Status         ServiceStatus `db:"status" json:"status"`
	EdgeHostname   string        `db:"edge_hostname" json:"edge_hostname"`
	FailureReason  *string       `db:"failure_reason" json:"failure_reason,omitempty"`
	Overage        bool          `db:"overage" json:"overage"`
	CreatedAt      time.Time     `db:"created_at" json:"created_at"`
	UpdatedAt      time.Time     `db:"updated_at" json:"updated_at"`
	ActivatedAt    *time.Time    `db:"activated_at" json:"activated_at,omitempty"`
	TerminatedAt   *time.Time    `db:"terminated_at" json:"terminated_at,omitempty"`
}

type Domain struct {
	ID                uuid.UUID  `db:"id" json:"id"`
	ServiceID         uuid.UUID  `db:"service_id" json:"service_id"`
	Domain            string     `db:"domain" json:"domain"`
	IsPrimary         bool       `db:"is_primary" json:"is_primary"`
	SSLStatus         string     `db:"ssl_status" json:"ssl_status"`
	Verified          bool       `db:"verified" json:"verified"`
	VerificationToken string     `db:"verification_token" json:"-"`
	LastCheckedAt     *time.Time `db:"last_checked_at" json:"last_checked_at,omitempty"`
	CreatedAt         time.Time  `db:"created_at" json:"created_at"`
}

type LoaderMode string

const (
	LoaderLive    LoaderMode = "live"
	LoaderPreview LoaderMode = "preview"
)

type Loader struct {
	ID         uuid.UUID  `db:"id" json:"id"`
	ServiceID  uuid.UUID  `db:"service_id" json:"service_id"`
	LoaderID   string     `db:"loader_id" json:"loader_id"`
	Version    int        `db:"version" json:"version"`
	Mode       LoaderMode `db:"mode" json:"mode"`
	IsActive   bool       `db:"is_active" json:"is_active"`
	HitCount   int64      `db:"hit_count" json:"hit_count"`
	LastHitAt  *time.Time `db:"last_hit_at" json:"last_hit_at,omitempty"`
	SRIHash    *string    `db:"sri_hash" json:"sri_hash,omitempty"`
	CreatedAt  time.Time  `db:"created_at" json:"created_at"`
	RotatedAt  *time.Time `db:"rotated_at" json:"rotated_at,omitempty"`
}

type LoaderConfig struct {
	LoaderID     string         `db:"loader_id" json:"loader_id"`
	TriggerType  string         `db:"trigger_type" json:"trigger_type"`
	TriggerValue string         `db:"trigger_value" json:"trigger_value,omitempty"`
	CookieName   string         `db:"cookie_name" json:"cookie_name,omitempty"`
	RespectDNT   bool           `db:"respect_dnt" json:"respect_dnt"`
	AllowBots    bool           `db:"allow_bots" json:"allow_bots"`
	// New in 0005: alias + Facebook cookie mapping
	JSFileAlias   string                 `db:"js_file_alias" json:"js_file_alias"`
	FBPCookieName string                 `db:"fbp_cookie_name" json:"fbp_cookie_name"`
	FBCCookieName string                 `db:"fbc_cookie_name" json:"fbc_cookie_name"`
	HonorConsent  bool                   `db:"honor_consent" json:"honor_consent"`
	VendorMapping map[string]interface{} `db:"vendor_mapping" json:"vendor_mapping"`
	UpdatedAt     time.Time              `db:"updated_at" json:"updated_at"`
}

type CookieExtension struct {
	ID            uuid.UUID `db:"id" json:"id"`
	ServiceID     uuid.UUID `db:"service_id" json:"service_id"`
	CookieName    string    `db:"cookie_name" json:"cookie_name"`
	VendorURL     string    `db:"vendor_url" json:"vendor_url"`
	NewLifetimeS  int       `db:"new_lifetime_s" json:"new_lifetime_s"`
	CookieDomain  *string   `db:"cookie_domain" json:"cookie_domain,omitempty"`
	Path          string    `db:"path" json:"path"`
	Secure        bool      `db:"secure" json:"secure"`
	HTTPOnly      bool      `db:"http_only" json:"http_only"`
	SameSite      string    `db:"same_site" json:"same_site"`
	IsActive      bool      `db:"is_active" json:"is_active"`
	LastUsedAt    *time.Time `db:"last_used_at" json:"last_used_at,omitempty"`
	HitCount      int64     `db:"hit_count" json:"hit_count"`
	CreatedAt     time.Time `db:"created_at" json:"created_at"`
	UpdatedAt     time.Time `db:"updated_at" json:"updated_at"`
}