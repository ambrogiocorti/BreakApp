#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${SUPABASE_DB_URL:?Configure the database connection in the secret manager}"
: "${BACKUP_PASSPHRASE:?Configure a separate backup encryption passphrase}"
if [ "${#BACKUP_PASSPHRASE}" -lt 32 ]; then
  echo 'The backup passphrase must contain at least 32 characters.' >&2
  exit 1
fi
destination="${1:-./backup-output}"
mkdir -p "$destination"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
mkdir -m 700 "$temporary/gnupg"
name="breakapp-$(date -u +%Y%m%dT%H%M%SZ).dump.gpg"
pg_dump --dbname="$SUPABASE_DB_URL" --format=custom --no-owner \
  --schema=public --schema=app_private --schema=auth --schema=storage --file="$temporary/database.dump"
pg_restore --list "$temporary/database.dump" > "$temporary/contents.txt"
test -s "$temporary/contents.txt"
printf '%s' "$BACKUP_PASSPHRASE" | gpg --homedir "$temporary/gnupg" --batch --yes --pinentry-mode loopback \
  --passphrase-fd 0 --symmetric --cipher-algo AES256 \
  --output "$destination/$name" "$temporary/database.dump"
sha256sum "$destination/$name" > "$destination/$name.sha256"
echo "Encrypted backup created: $name"
