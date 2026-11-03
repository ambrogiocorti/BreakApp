#!/usr/bin/env bash
# Synthetic fixture: no Supabase credentials or real student files.
set -euo pipefail
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
mkdir -p "$temp/snapshot/buckets/images" "$temp/out"
printf 'synthetic-breakapp-object-test\n' > "$temp/snapshot/buckets/images/example.txt"
printf '{"format":"breakapp-storage-snapshot-v1","total_objects":1}\n' > "$temp/snapshot/snapshot-manifest.json"
export BACKUP_PASSPHRASE='test-only-archive-key-with-over-32-characters'
bash scripts/create-encrypted-storage-archive.sh "$temp/snapshot" "$temp/out"
shopt -s nullglob
files=("$temp/out"/*.tar.gpg)
[ "${#files[@]}" -eq 1 ] || { echo 'Expected one encrypted archive' >&2; exit 1; }
(cd "$temp/out" && sha256sum -c "${files[0]##*/}.sha256")
restored="$(gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
  --decrypt "${files[0]}" 3< <(printf '%s' "$BACKUP_PASSPHRASE") \
  | tar -xOf - './buckets/images/example.txt')"
[ "$restored" = 'synthetic-breakapp-object-test' ] || {
  echo 'Encrypted Storage payload could not be restored' >&2; exit 1;
}
if gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
   --decrypt "${files[0]}" 3< <(printf 'deliberately-incorrect-backup-passphrase') \
   >/dev/null 2>&1; then
  echo 'Wrong backup passphrase unexpectedly succeeded' >&2
  exit 1
fi
echo 'Storage archive encryption / decryption / integrity fixture passed.'
