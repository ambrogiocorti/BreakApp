#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${BACKUP_PASSPHRASE:?Load the backup passphrase from the separate secret manager}"
source_file="${1:?Pass the encrypted .dump.gpg file}"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
printf '%s' "$BACKUP_PASSPHRASE" | gpg --batch --yes --pinentry-mode loopback \
  --passphrase-fd 0 --decrypt --output "$temporary/database.dump" "$source_file"
pg_restore --list "$temporary/database.dump" > "$temporary/contents.txt"
test -s "$temporary/contents.txt"
if [ -n "${RESTORE_TEST_DB_URL:-}" ]; then
  # This target must be a newly created, disposable database, never production.
  pg_restore --dbname="$RESTORE_TEST_DB_URL" --no-owner \
    --exit-on-error --single-transaction "$temporary/database.dump"
fi
echo 'Encrypted archive authenticated and readable.'
