#!/usr/bin/env bash
# Runs every migration and every test against a throwaway local Postgres database.
# Usage: supabase/tests/run_local.sh [admin_database_url]
# Example: supabase/tests/run_local.sh postgresql://postgres:postgres@localhost:5432/postgres
set -euo pipefail
cd "$(dirname "$0")/../.."
DB_URL="${1:-${DATABASE_URL:-postgresql://postgres:postgres@localhost:5432/postgres}}"
TEST_DB="khatabook_test_$$"
BASE="${DB_URL%/*}"
TEST_URL="$BASE/$TEST_DB"
psql -q -v ON_ERROR_STOP=1 -d "$DB_URL" -c "create database $TEST_DB"
trap 'psql -q -d "$DB_URL" -c "drop database if exists $TEST_DB" >/dev/null' EXIT
psql -q -v ON_ERROR_STOP=1 -d "$TEST_URL" -f supabase/tests/00_auth_shim.sql
for f in supabase/migrations/*.sql; do
  echo "applying $f"
  psql -q -v ON_ERROR_STOP=1 -d "$TEST_URL" -f "$f"
done
status=0
for t in supabase/tests/[0-9][0-9]_*_test.sql; do
  echo "running $t"
  if ! psql -q -v ON_ERROR_STOP=1 -d "$TEST_URL" -f "$t" 2>&1 | grep -vE 'NOTICE:  ok'; then status=1; fi
  # grep exits 1 when nothing but ok lines came through, which is success; re check with psql's own status
  if ! psql -q -v ON_ERROR_STOP=1 -d "$TEST_URL" -c 'select 1' >/dev/null; then status=1; fi
done
exit $status
