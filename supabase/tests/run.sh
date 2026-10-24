#!/usr/bin/env bash
# Runs the migrations and invariant tests on a scratch Postgres database.
# Usage: PGHOST=127.0.0.1 PGPORT=54329 PGUSER=postgres supabase/tests/run.sh
# pg_cron is not available on plain Postgres, so the cron migration is skipped.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
db="booking_test"

psql -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists $db" -c "create database $db"
# roles are cluster-wide; drop leftovers from a previous run
psql -q -d postgres -c "drop role if exists anon" -c "drop role if exists authenticated" -c "drop role if exists service_role" >/dev/null 2>&1 || true

psql -v ON_ERROR_STOP=1 -q -d "$db" -f "$here/shim.sql"
for f in "$here"/../migrations/*.sql; do
  case "$f" in *_cron.sql) continue ;; esac
  psql -v ON_ERROR_STOP=1 -q -d "$db" -f "$f"
done
psql -v ON_ERROR_STOP=1 -q -tA -d "$db" -f "$here/invariants.sql" 2>&1 | grep -E "ok  |FAIL|ERROR|passed" | sed -E "s/^psql:[^ ]+ NOTICE:  //"
exit "${PIPESTATUS[0]}"
