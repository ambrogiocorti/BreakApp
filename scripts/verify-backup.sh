#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${BACKUP_PASSPHRASE:?Load the backup passphrase from the separate secret manager}"
source_file="${1:?Pass the encrypted .dump.gpg file}"
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
mkdir -m 700 "$temporary/gnupg"
printf '%s' "$BACKUP_PASSPHRASE" | gpg --homedir "$temporary/gnupg" --batch --yes --pinentry-mode loopback \
  --passphrase-fd 0 --decrypt --output "$temporary/database.dump" "$source_file"
pg_restore --list "$temporary/database.dump" > "$temporary/contents.txt"
test -s "$temporary/contents.txt"
if [ -n "${RESTORE_TEST_DB_URL:-}" ]; then
  # This target must be a newly created, disposable database, never production.
  existing="$(psql --dbname="$RESTORE_TEST_DB_URL" -XAt --set ON_ERROR_STOP=1 --command="select count(*) from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','app_private','auth','storage') and c.relkind in ('r','p','v','m','S','f')")"
  if [ "$existing" -ne 0 ]; then
    echo 'Restore refused: the target database already contains application objects.' >&2
    exit 1
  fi
  pg_restore --dbname="$RESTORE_TEST_DB_URL" --no-owner --clean --if-exists \
    --exit-on-error --single-transaction "$temporary/database.dump"
fi
echo 'Encrypted archive authenticated and readable.'
