#!/usr/bin/env bash
# Runs the SQL tests against a fresh database.
#
#   ./run.sh                      # uses the PG* environment variables (e.g. in CI)
#   PGHOST=localhost PGUSER=postgres PGPASSWORD=postgres ./run.sh
#
# The database named by PGDATABASE (default: bamboozled_test) is dropped and recreated.
set -euo pipefail
cd "$(dirname "$0")"

DB="${PGDATABASE:-bamboozled_test}"
admin() { PGDATABASE=postgres psql -v ON_ERROR_STOP=1 -q "$@"; }
db() { PGDATABASE="$DB" psql -v ON_ERROR_STOP=1 -q "$@"; }

admin -c "drop database if exists \"$DB\" with (force)" -c "create database \"$DB\""
db -f 00_supabase_stub.sql
db -f ../migrations/0001_tasks.sql
db -f ../migrations/0002_task_link.sql
db -f ../migrations/0002_task_link.sql # running it twice must be harmless
for t in 01_schema_test.sql 02_task_link_test.sql; do
  db -f "$t" 2>&1 | grep -E "^psql:.*(NOTICE|ERROR)|^ERROR" | sed -E 's/^psql:[^ ]+ NOTICE:  /  /'
  test "${PIPESTATUS[0]}" -eq 0 || { echo "SQL tests FAILED"; exit 1; }
done
echo "SQL tests passed"
