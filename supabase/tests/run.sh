#!/usr/bin/env bash
# Sobe um Postgres temporário, aplica a migração e roda os testes. Precisa de Postgres 14+ instalado.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PGBIN="${PGBIN:-$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -1)}"
DIR="$(mktemp -d)"; PORT="${PGPORT:-54329}"
chown -R postgres "$DIR" 2>/dev/null || true
RUN="su postgres -c"; [ "$(id -u)" != 0 ] && RUN="bash -c"
$RUN "$PGBIN/initdb -D $DIR/data -A trust -U postgres >/dev/null"
$RUN "$PGBIN/pg_ctl -D $DIR/data -o '-p $PORT -k $DIR' -l $DIR/log -w start >/dev/null"
trap "$RUN \"$PGBIN/pg_ctl -D $DIR/data -m immediate stop >/dev/null\"; rm -rf $DIR" EXIT
export PGHOST="$DIR" PGPORT="$PORT" PGUSER=postgres PGOPTIONS='-c search_path=public,extensions -c client_min_messages=notice'
chmod -R a+rX "$HERE"
psql -v ON_ERROR_STOP=1 -q -d postgres -c "create database belezando_test"
export PGDATABASE=belezando_test
psql -v ON_ERROR_STOP=1 -q -f "$HERE/00_stub_supabase.sql"
for f in "${MIG_DIR:-$HERE/../migrations}"/*.sql; do psql -v ON_ERROR_STOP=1 -q -f "$f"; done
psql -v ON_ERROR_STOP=1 -q -t -A -f "$HERE/10_rls.test.sql" 2>&1 | sed -e "s/^psql:[^ ]* //" | grep -E "ok  -|FALHOU|TODOS|ERROR" || { echo FALHA; exit 1; }
