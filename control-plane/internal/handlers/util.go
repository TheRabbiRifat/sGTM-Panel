package handlers

import (
	"time"

	"github.com/hostaffin/sgtm/control-plane/internal/repos"
)

// timeNow is overridable in tests.
var timeNow = time.Now

// auditEntry is a helper for building audit entries.
func auditEntry(actor, action, resource string, meta map[string]any) repos.AuditEntry {
	return repos.AuditEntry{
		ActorType: actor,
		Action:    action,
		Resource:  resource,
		Metadata:  meta,
	}
}