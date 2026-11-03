#!/usr/bin/env bash
# Encrypt an entire, already-validated local Storage snapshot.
# The plaintext snapshot must reside on a short-lived private runner volume.
set -euo pipefail
umask 077
: "${BACKUP_PASSPHRASE:?Load the backup encryption passphrase from the secret manager}"
if [ "${#BACKUP_PASSPHRASE}" -lt 32 ]; then
  echo 'BACKUP_PASSPHRASE must contain at least 32 characters.' >&2
  exit 1
fi
source_dir="${1:?Pass the private snapshot directory}"
destination="${2:?Pass the encrypted output directory}"
[ -d "$source_dir" ] || { echo 'Snapshot directory is missing.' >&2; exit 1; }
mkdir -p "$destination"
destination="$(cd "$destination" && pwd -P)"
source_dir="$(cd "$source_dir" && pwd -P)"
case "$destination/" in "$source_dir/"*) echo 'Encrypted output cannot be inside the plaintext snapshot.' >&2; exit 1;; esac
temporary="$(mktemp -d)"
trap 'rm -rf "$temporary"' EXIT
mkdir -m 700 "$temporary/gnupg"
name="breakapp-storage-$(date -u +%Y%m%dT%H%M%SZ).tar.gpg"
archive="$destination/$name"
# GnuPG reads the passphrase on FD 3, not via command-line arguments.
# The tar stream is never written to disk in cleartext.
if ! tar -C "$source_dir" -cf - . | \
    gpg --homedir "$temporary/gnupg" --batch --yes --pinentry-mode loopback \
      --passphrase-fd 3 --symmetric --cipher-algo AES256 \
      --output "$archive" 3< <(printf '%s' "$BACKUP_PASSPHRASE"); then
  rm -f "$archive"
  echo 'Storage archive encryption failed.' >&2
  exit 1
fi
[ -s "$archive" ] || { rm -f "$archive"; echo 'Empty encrypted storage archive.' >&2; exit 1; }
# Decryption + tar validation tests integrity of the encrypted stream.
if ! gpg --homedir "$temporary/gnupg" --batch --yes --pinentry-mode loopback \
    --passphrase-fd 3 --decrypt "$archive" 3< <(printf '%s' "$BACKUP_PASSPHRASE") \
      | tar -tf - > /dev/null; then
  rm -f "$archive"
  echo 'Storage archive verification failed.' >&2
  exit 1
fi
(cd "$destination" && sha256sum "$name" > "$name.sha256")
echo "Encrypted Storage snapshot created and verified: $name"
