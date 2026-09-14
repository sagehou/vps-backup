#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

ENV_FILE="$ROOT_DIR/central/.env.example"
COMPOSE_FILE="$ROOT_DIR/central/compose.yaml"
CHECK_UNIT="$ROOT_DIR/central/systemd/restic-check.service"
MAINT_UNIT="$ROOT_DIR/central/systemd/restic-maintenance.service"

# Provider-neutral crypt remote is the stable API presented to both gateways.
grep -Fq 'RCLONE_REMOTE=backup-crypt:restic' "$ENV_FILE" || \
  fail 'central/.env.example must use backup-crypt:restic'

if grep -Fq 'backup-onedrive-crypt' "$ENV_FILE" "$COMPOSE_FILE" "$ROOT_DIR/README.md" "$ROOT_DIR/docs/rclone-backends.md"; then
  fail 'active templates/docs must not bind the crypt remote name to OneDrive'
fi

# restic-admin runs as a non-root user and therefore needs an explicit writable cache.
grep -Fq 'RESTIC_CACHE_DIR: "/cache"' "$COMPOSE_FILE" || \
  fail 'restic-admin must set RESTIC_CACHE_DIR=/cache'
grep -Fq './cache/restic:/cache:rw' "$COMPOSE_FILE" || \
  fail 'restic-admin must mount the persistent cache directory'

for UNIT in "$CHECK_UNIT" "$MAINT_UNIT"; do
  grep -Fq 'ExecStartPre=/usr/bin/install -d -o 10001 -g 10001 -m 0750 /data/restic-gateway/cache/restic /data/restic-gateway/locks' "$UNIT" || \
    fail "$(basename "$UNIT") must prepare cache and lock directories"
  grep -Fq '/data/restic-gateway/locks/admin.lock' "$UNIT" || \
    fail "$(basename "$UNIT") must use the shared admin lock"
done

echo 'central config regression test OK'
