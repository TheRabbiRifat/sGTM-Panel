package handlers

import (
	"github.com/hostaffin/sgtm/control-plane/internal/repos"
)

func newUserRepo(d *Deps) *repos.UserRepo       { return repos.NewUserRepo(d.DB.DB) }
func newPlanRepo(d *Deps) *repos.PlanRepo       { return repos.NewPlanRepo(d.DB.DB) }
func newNodeRepo(d *Deps) *repos.NodeRepo       { return repos.NewNodeRepo(d.DB.DB) }
func newServiceRepo(d *Deps) *repos.ServiceRepo { return repos.NewServiceRepo(d.DB.DB) }
func newDomainRepo(d *Deps) *repos.DomainRepo   { return repos.NewDomainRepo(d.DB.DB) }
func newLoaderRepo(d *Deps) *repos.LoaderRepo   { return repos.NewLoaderRepo(d.DB.DB) }
func newCookieExtRepo(d *Deps) *repos.CookieExtRepo {
	return repos.NewCookieExtRepo(d.DB.DB)
}
func newAuditRepo(d *Deps) *repos.AuditRepo     { return repos.NewAuditRepo(d.DB.DB) }
func newUsageRepo(d *Deps) *repos.UsageRepo     { return repos.NewUsageRepo(d.DB.DB) }