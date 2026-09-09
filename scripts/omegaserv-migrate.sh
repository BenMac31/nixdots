#!/usr/bin/env bash
# Migration steps for omegaServ that NixOS cannot express declaratively.
# Run as an unprivileged user in the wheel group; it escalates per command.
set -euo pipefail

DOCKER_ROOT=/home/docker
CONDUIT_SRC="$DOCKER_ROOT/volumes/conduit_db/_data"
CONDUIT_DST=/home/continuwuity
MAUTRIX_SRC=/srv/mautrix/db
MAUTRIX_WORK=/home/mautrix-db-migration
AIO_DUMP="$DOCKER_ROOT/volumes/nextcloud_aio_database_dump/_data"
WORK="${TMPDIR:-/tmp}/omegaserv-migrate"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[31mx\033[0m %s\n' "$*" >&2; exit 1; }

confirm() {
  local reply
  read -r -p "  $1 [y/N] " reply
  [[ $reply == [yY] ]] || { info "skipped"; return 1; }
}

require_user() {
  [[ $EUID -ne 0 ]] || die "run this as your own user, not root; it uses sudo where it needs to"
  sudo -v || die "cannot sudo"
}

# --------------------------------------------------------------------------
status() {
  bold "== omegaServ migration status"

  if sudo test -e "$CONDUIT_DST/CURRENT"; then
    ok "Matrix database staged at $CONDUIT_DST ($(sudo du -sh "$CONDUIT_DST" | cut -f1))"
  else
    warn "Matrix database not staged at $CONDUIT_DST — run: $0 matrix-db"
  fi

  local unit
  for unit in continuwuity mautrix-whatsapp mautrix-discord postgresql docker; do
    if systemctl list-unit-files "$unit.service" >/dev/null 2>&1 &&
       [[ -n $(systemctl list-unit-files --no-legend "$unit.service" 2>/dev/null) ]]; then
      info "$(printf '%-18s %s' "$unit" "$(systemctl is-active "$unit.service" 2>/dev/null || true)")"
    else
      warn "$(printf '%-18s %s' "$unit" "not deployed")"
    fi
  done

  local reg
  for reg in /var/lib/mautrix-whatsapp/whatsapp-registration.yaml \
             /var/lib/mautrix-discord/discord-registration.yaml; do
    if sudo test -f "$reg"; then ok "registration present: $reg"
    else warn "registration not yet generated: $reg"; fi
  done

  if sudo test -f "$AIO_DUMP/export.failed"; then
    warn "stale AIO export.failed marker present — run: $0 aio"
  else
    ok "no stale AIO export marker"
  fi
}

# --------------------------------------------------------------------------
matrix_db() {
  bold "== stage the conduwuit database"
  sudo test -d "$CONDUIT_SRC" || die "$CONDUIT_SRC not found"

  if sudo test -e "$CONDUIT_DST/CURRENT"; then
    ok "already staged at $CONDUIT_DST — nothing to do"
    return 0
  fi

  info "copying $CONDUIT_SRC -> $CONDUIT_DST ($(sudo du -sh "$CONDUIT_SRC" | cut -f1))"
  confirm "proceed?" || return 0

  sudo install -d -m 0700 "$CONDUIT_DST"
  sudo cp -a --reflink=auto "$CONDUIT_SRC/." "$CONDUIT_DST/"
  ok "staged $(sudo du -sh "$CONDUIT_DST" | cut -f1); the source volume is untouched"
  info "continuwuity migrates the 0.4.7 schema on first start — that can take minutes"
}

# --------------------------------------------------------------------------
# The old bridge state is a Docker Postgres data directory. Postgres must be
# the matching major to read it, and starting one writes to the directory, so
# this works on a copy and leaves /srv/mautrix/db pristine.
bridge_db() {
  bold "== recover the mautrix bridge databases"
  sudo test -d "$MAUTRIX_SRC" || die "$MAUTRIX_SRC not found"

  local pgver
  pgver=$(sudo cat "$MAUTRIX_SRC/PG_VERSION")
  info "old data directory is PostgreSQL $pgver"

  mkdir -p "$WORK"

  if ! sudo test -f "$MAUTRIX_WORK/PG_VERSION"; then
    info "copying $MAUTRIX_SRC -> $MAUTRIX_WORK ($(sudo du -sh "$MAUTRIX_SRC" | cut -f1))"
    confirm "proceed?" || return 0
    sudo rm -rf "$MAUTRIX_WORK"
    sudo cp -a --reflink=auto "$MAUTRIX_SRC" "$MAUTRIX_WORK"
  else
    ok "working copy already at $MAUTRIX_WORK"
  fi

  info "starting postgres:$pgver against the copy"
  sudo docker rm -f mautrix_dump >/dev/null 2>&1 || true
  sudo docker run --rm -d --name mautrix_dump \
    -v "$MAUTRIX_WORK:/var/lib/postgresql/data" \
    -e POSTGRES_PASSWORD=unused \
    "postgres:$pgver" >/dev/null

  local i
  for i in $(seq 1 60); do
    sudo docker exec mautrix_dump pg_isready -q && break
    [[ $i -eq 60 ]] && { sudo docker logs --tail 20 mautrix_dump; die "postgres never became ready"; }
    sleep 1
  done
  ok "postgres up"

  # POSTGRES_MULTIPLE_DATABASES was "database,discord,slack"; whatsapp used
  # "database". Slack is out of scope.
  sudo docker exec mautrix_dump pg_dump -U funnylemon --no-owner --no-acl -d database \
    | sudo tee "$WORK/whatsapp.sql" >/dev/null
  sudo docker exec mautrix_dump pg_dump -U funnylemon --no-owner --no-acl -d discord \
    | sudo tee "$WORK/discord.sql" >/dev/null
  sudo docker stop mautrix_dump >/dev/null
  ok "dumped: $(du -sh "$WORK/whatsapp.sql" | cut -f1) whatsapp, $(du -sh "$WORK/discord.sql" | cut -f1) discord"

  bold "-- restore into the NixOS PostgreSQL"
  warn "the bridges must not have written their own schema yet; this stops them first"
  confirm "restore now?" || { info "dumps kept in $WORK"; return 0; }

  sudo systemctl stop mautrix-whatsapp mautrix-discord 2>/dev/null || true
  sudo -u postgres psql -v ON_ERROR_STOP=1 -d mautrix-whatsapp -f "$WORK/whatsapp.sql"
  sudo -u postgres psql -v ON_ERROR_STOP=1 -d mautrix-discord  -f "$WORK/discord.sql"
  ok "restored; bridges left stopped so you can register them first"
}

# --------------------------------------------------------------------------
bridge_reg() {
  bold "== generate appservice registrations"
  info "continuwuity has no appservice config option; registration happens in"
  info "the admin room at runtime. Starting each bridge writes its YAML."

  sudo systemctl start mautrix-whatsapp mautrix-discord 2>/dev/null || true
  info "bridges started; they will fail to reach the homeserver until registered"
  sleep 3

  local reg
  for reg in /var/lib/mautrix-whatsapp/whatsapp-registration.yaml \
             /var/lib/mautrix-discord/discord-registration.yaml; do
    echo
    if sudo test -f "$reg"; then
      bold "---- $reg"
      sudo cat "$reg"
    else
      warn "not generated: $reg"
      info "check: journalctl -u $(basename "$(dirname "$reg")") -n 40"
    fi
  done

  echo
  bold "-- next, by hand"
  info "1. open the continuwuity admin room"
  info "2. run '!admin help' and confirm the appservice register syntax for this build"
  info "3. register each YAML above"
  info "4. sudo systemctl restart mautrix-whatsapp mautrix-discord"
}

# --------------------------------------------------------------------------
aio() {
  bold "== clear stale Nextcloud AIO export markers"
  local f moved=0
  for f in export.failed database-dump.sql.temp; do
    if sudo test -f "$AIO_DUMP/$f"; then
      info "$f present ($(sudo stat -c %y "$AIO_DUMP/$f" | cut -d. -f1))"
      if confirm "move $f aside to $f.bak?"; then
        sudo mv "$AIO_DUMP/$f" "$AIO_DUMP/$f.bak"
        moved=1
      fi
    fi
  done
  if [[ $moved -eq 1 ]]; then ok "moved aside, not deleted"; else ok "nothing to clear"; fi

  info "the good dump is still $AIO_DUMP/database-dump.sql — do not delete it"
  info "AIO's live database is the authoritative copy; that file is a stale fallback"
}

# --------------------------------------------------------------------------
usage() {
  cat <<'EOF'
omegaserv-migrate.sh <command>

  status      what is done and what is not
  matrix-db   stage the conduwuit RocksDB into /home/continuwuity
  bridge-db   dump the old mautrix Postgres and restore it into NixOS Postgres
  bridge-reg  start the bridges, print their appservice registrations
  aio         move stale Nextcloud AIO export markers aside

Nothing here deletes anything under /home/docker.
Deploy first: nixos-rebuild switch --flake .#omegaServ
EOF
}

require_user
case "${1:-}" in
  status)     status ;;
  matrix-db)  matrix_db ;;
  bridge-db)  bridge_db ;;
  bridge-reg) bridge_reg ;;
  aio)        aio ;;
  *)          usage; exit 1 ;;
esac
