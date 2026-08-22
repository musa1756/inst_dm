#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

PROJECT_DIR="${INSTDM_PROJECT_DIR:-/opt/inst_dm}"
BACKUP_DIR="${INSTDM_BACKUP_DIR:-/var/backups/inst_dm}"
RETENTION_DAYS="${INSTDM_BACKUP_RETENTION_DAYS:-14}"
BACKUP_KIND="${1:-manual}"

case "$BACKUP_KIND" in
  scheduled|manual|pre-deploy|pre-restore) ;;
  *)
    echo "Unknown backup kind: $BACKUP_KIND" >&2
    exit 2
    ;;
esac

if [[ ! "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || (( RETENTION_DAYS < 1 || RETENTION_DAYS > 365 )); then
  echo "INSTDM_BACKUP_RETENTION_DAYS must be between 1 and 365." >&2
  exit 2
fi

if [[ ! -f "$PROJECT_DIR/docker-compose.yml" || ! -f "$PROJECT_DIR/.env" ]]; then
  echo "Inst DM installation was not found at $PROJECT_DIR." >&2
  exit 2
fi

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
BACKUP_DIR="$(readlink -f "$BACKUP_DIR")"

case "$BACKUP_DIR" in
  /|/var|/var/backups|"")
    echo "Unsafe backup directory: $BACKUP_DIR" >&2
    exit 2
    ;;
esac

exec 9>"$BACKUP_DIR/.backup.lock"
if ! flock -n 9; then
  echo "Another Inst DM backup is already running." >&2
  exit 3
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
archive_name="inst_dm-${BACKUP_KIND}-${timestamp}.tar.gz"
archive_path="$BACKUP_DIR/$archive_name"
partial_path="$BACKUP_DIR/.${archive_name}.partial"
work_dir="$(mktemp -d "$BACKUP_DIR/.backup-${timestamp}-XXXXXX")"

cleanup() {
  rm -rf -- "$work_dir"
  rm -f -- "$partial_path"
}
trap cleanup EXIT

cd "$PROJECT_DIR"

docker compose exec -T db sh -lc \
  'exec pg_dump --username="$POSTGRES_USER" --dbname="$POSTGRES_DB" --format=custom --compress=9 --no-owner --no-privileges' \
  > "$work_dir/database.dump"

if [[ ! -s "$work_dir/database.dump" ]]; then
  echo "PostgreSQL produced an empty dump." >&2
  exit 4
fi

docker compose exec -T db pg_restore --list < "$work_dir/database.dump" > /dev/null
install -m 600 "$PROJECT_DIR/.env" "$work_dir/production.env"

app_version="$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$PROJECT_DIR/package.json" | head -n 1)"
cat > "$work_dir/manifest.txt" <<EOF
created_at_utc=$timestamp
kind=$BACKUP_KIND
app_version=${app_version:-unknown}
contents=database.dump,production.env
EOF

tar -C "$work_dir" -czf "$partial_path" database.dump production.env manifest.txt
tar -tzf "$partial_path" > /dev/null
mv "$partial_path" "$archive_path"
chmod 600 "$archive_path"

(
  cd "$BACKUP_DIR"
  sha256sum "$archive_name" > "$archive_name.sha256"
  chmod 600 "$archive_name.sha256"
)

find "$BACKUP_DIR" -maxdepth 1 -type f \
  \( -name 'inst_dm-*.tar.gz' -o -name 'inst_dm-*.tar.gz.sha256' \) \
  -mtime "+$RETENTION_DAYS" -delete

echo "$archive_path"
