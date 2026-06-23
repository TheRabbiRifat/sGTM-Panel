package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/hostaffin/sgtm/control-plane/internal/config"
	"github.com/hostaffin/sgtm/control-plane/internal/db"
)

// Minimal migration runner: applies *.up.sql from ./migrations in order,
// tracks applied versions in schema_migrations.

func main() {
	if len(os.Args) < 2 {
		fmt.Println("usage: migrate <up|down>")
		os.Exit(2)
	}
	cmd := os.Args[1]

	cfg := config.Load()
	pg, err := db.NewPostgres(cfg.DatabaseURL, 2, 1)
	if err != nil {
		fmt.Println("connect:", err)
		os.Exit(1)
	}
	defer pg.Close()

	if _, err := pg.Exec(`CREATE TABLE IF NOT EXISTS schema_migrations (
		version BIGINT PRIMARY KEY,
		applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
	)`); err != nil {
		fmt.Println("create schema_migrations:", err)
		os.Exit(1)
	}

	dir := "migrations"
	if v := os.Getenv("MIGRATIONS_DIR"); v != "" {
		dir = v
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		fmt.Println("read dir:", err)
		os.Exit(1)
	}

	var files []string
	suffix := "." + cmd + ".sql"
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), suffix) {
			files = append(files, filepath.Join(dir, e.Name()))
		}
	}
	sort.Strings(files)

	if cmd == "down" {
		// reverse order
		sort.Sort(sort.Reverse(sort.StringSlice(files)))
	}

	for _, f := range files {
		version, err := parseVersion(f)
		if err != nil {
			fmt.Println("parse:", err)
			os.Exit(1)
		}
		applied, err := isApplied(pg, version)
		if err != nil {
			fmt.Println("check:", err)
			os.Exit(1)
		}
		if cmd == "up" && applied {
			fmt.Printf("skip %s (already applied)\n", f)
			continue
		}
		if cmd == "down" && !applied {
			fmt.Printf("skip %s (not applied)\n", f)
			continue
		}

		buf, err := os.ReadFile(f)
		if err != nil {
			fmt.Println("read:", err)
			os.Exit(1)
		}
		fmt.Printf("applying %s ... ", f)
		if _, err := pg.Exec(string(buf)); err != nil {
			fmt.Println("FAIL:", err)
			os.Exit(1)
		}
		if cmd == "up" {
			_, _ = pg.Exec("INSERT INTO schema_migrations(version) VALUES($1)", version)
		} else {
			_, _ = pg.Exec("DELETE FROM schema_migrations WHERE version=$1", version)
		}
		fmt.Println("ok")
	}
	fmt.Println("done")
}

func parseVersion(path string) (int64, error) {
	base := filepath.Base(path)
	parts := strings.SplitN(base, "_", 2)
	return strconv.ParseInt(parts[0], 10, 64)
}

func isApplied(pg *db.Postgres, v int64) (bool, error) {
	if pg == nil {
		return false, errors.New("nil pg")
	}
	var n int
	err := pg.QueryRow("SELECT COUNT(*) FROM schema_migrations WHERE version=$1", v).Scan(&n)
	return n > 0, err
}