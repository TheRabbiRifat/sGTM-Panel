package main

import (
	"fmt"
	"os"

	"github.com/hostaffin/sgtm/control-plane/internal/auth"
	"github.com/hostaffin/sgtm/control-plane/internal/config"
	"github.com/hostaffin/sgtm/control-plane/internal/db"
)

func main() {
	cfg := config.Load()
	pg, err := db.NewPostgres(cfg.DatabaseURL, 2, 1)
	if err != nil {
		fmt.Println("connect:", err)
		os.Exit(1)
	}
	defer pg.Close()

	// Plans
	plans := []struct {
		whmcsPID int
		slug     string
		name     string
		cpu      float64
		ram      int
		req      int64
		bw       int
		price    int
	}{
		{1, "starter", "Starter", 0.5, 512, 500_000, 10, 1900},
		{2, "growth", "Growth", 1.0, 1024, 2_000_000, 50, 4900},
		{3, "agency", "Agency", 2.0, 2048, 10_000_000, 200, 14900},
	}
	for _, p := range plans {
		_, err := pg.Exec(`INSERT INTO plans
			(whmcs_product_id, name, slug, cpu_limit, ram_limit_mb,
			 request_limit, bandwidth_limit_gb, price_cents, currency, is_active)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,'USD', TRUE)
			ON CONFLICT (slug) DO UPDATE SET
				name=EXCLUDED.name,
				cpu_limit=EXCLUDED.cpu_limit,
				ram_limit_mb=EXCLUDED.ram_limit_mb,
				request_limit=EXCLUDED.request_limit,
				bandwidth_limit_gb=EXCLUDED.bandwidth_limit_gb,
				price_cents=EXCLUDED.price_cents`,
			p.whmcsPID, p.name, p.slug, p.cpu, p.ram, p.req, p.bw, p.price)
		if err != nil {
			fmt.Println("plan", p.slug, err)
		}
	}

	// Bootstrap admin
	email := cfg.AdminBootstrapEmail
	if email == "" {
		email = "admin@hostaffin.local"
	}
	pwd := cfg.AdminBootstrapPassword
	if pwd == "" {
		pwd = "ChangeMe!123"
	}
	hash, err := auth.HashPassword(pwd)
	if err != nil {
		fmt.Println("hash:", err)
		os.Exit(1)
	}
	_, err = pg.Exec(`INSERT INTO users (email, password, role, is_active)
		VALUES ($1,$2,'super_admin',TRUE)
		ON CONFLICT (email) DO UPDATE SET password=EXCLUDED.password, is_active=TRUE`,
		email, hash)
	if err != nil {
		fmt.Println("admin:", err)
		os.Exit(1)
	}

	fmt.Println("seed complete: 3 plans + 1 super_admin")
	fmt.Println("admin login:", email)
}