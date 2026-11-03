#!/usr/bin/env bash
# Fully offline fake S3 API fixture; never touches Supabase or user buckets.
set -euo pipefail
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
mkdir -p "$temp/mockbin" "$temp/out"
printf 'synthetic school product image\n' > "$temp/object.bin"
cat > "$temp/mockbin/aws" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
# Verify the production script explicitly configures the Python classic client.
if [ "${1-}" = configure ] && [ "${2-}" = get ] && [ "${3-}" = s3.preferred_transfer_client ]; then
  test -f "${AWS_CONFIG_FILE:-}" || exit 19
  grep -Eq '^[[:space:]]*preferred_transfer_client = classic
  's3api list-buckets')
    printf '%s\n' '{"Buckets":[{"Name":"breakapp-product-images"},{"Name":"breakapp-ticket-images"}]}'
    ;;
  's3api list-objects-v2')
    bucket=''
    while [ "$#" -gt 0 ]; do
      if [ "$1" = '--bucket' ]; then bucket="$2";break; fi
      shift
    done
    case "$bucket" in
      breakapp-product-images)
        size="$(wc -c < "$TEST_AWS_OBJECT" | tr -d ' ')"
        printf '{"Contents":[{"Key":"products/Screenshot 2026-10-27 155847.png","Size":%s}]}\n' "$size"
        ;;
      breakapp-ticket-images) printf '%s\n' '{"Contents":[]}' ;;
      *) exit 16 ;;
    esac
    ;;
  's3 sync')
    case "${5-}" in
      s3://breakapp-product-images/)
        mkdir -p "$6/products"
        cp "$TEST_AWS_OBJECT" "$6/products/Screenshot 2026-10-27 155847.png"
        ;;
      s3://breakapp-ticket-images/) mkdir -p "$6" ;;
      *) exit 17 ;;
    esac
    ;;
  *) echo 'unexpected mock AWS invocation' >&2;exit 18 ;;
esac
MOCK
chmod 700 "$temp/mockbin/aws"
export PATH="$temp/mockbin:$PATH"
export TEST_AWS_OBJECT="$temp/object.bin"
export SUPABASE_STORAGE_S3_ENDPOINT='https://ynvswdyirngvdpudcikl.storage.supabase.co/storage/v1/s3'
export SUPABASE_STORAGE_S3_REGION='eu-west-1'
export AWS_ACCESS_KEY_ID='fake-id-for-unit-test'
export AWS_SECRET_ACCESS_KEY='fake-secret-for-unit-test'
export BACKUP_PASSPHRASE='synthetic-archive-passphrase-over-32-characters'
bash scripts/backup-storage-s3.sh "$temp/out"
shopt -s nullglob
archives=("$temp/out"/*.tar.gpg)
[ "${#archives[@]}" -eq 1 ] || { echo 'S3 snapshot was not archived' >&2;exit 1; }
manifest="$(gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
  --decrypt "${archives[0]}" 3< <(printf '%s' "$BACKUP_PASSPHRASE") \
  | tar -xOf - './snapshot-manifest.json')"
printf '%s' "$manifest" | python3 -c '
import json,sys
m=json.load(sys.stdin)
assert m["format"]=="breakapp-storage-snapshot-v1"
assert len(m["buckets"])==2
assert m["total_objects"]==1
assert len(m["buckets"][0]["objects"])==1
assert m["buckets"][0]["objects"][0]["key"]=="products/Screenshot 2026-10-27 155847.png"
print("Complete multi-bucket fake S3 snapshot and encrypted manifest verified")
'
 "$AWS_CONFIG_FILE" || exit 20
  grep -Eq '^[[:space:]]*addressing_style = path
  's3api list-buckets')
    printf '%s\n' '{"Buckets":[{"Name":"breakapp-product-images"},{"Name":"breakapp-ticket-images"}]}'
    ;;
  's3api list-objects-v2')
    bucket=''
    while [ "$#" -gt 0 ]; do
      if [ "$1" = '--bucket' ]; then bucket="$2";break; fi
      shift
    done
    case "$bucket" in
      breakapp-product-images)
        size="$(wc -c < "$TEST_AWS_OBJECT" | tr -d ' ')"
        printf '{"Contents":[{"Key":"products/test.bin","Size":%s}]}\n' "$size"
        ;;
      breakapp-ticket-images) printf '%s\n' '{"Contents":[]}' ;;
      *) exit 16 ;;
    esac
    ;;
  's3 sync')
    case "${5-}" in
      s3://breakapp-product-images/)
        mkdir -p "$6/products"
        cp "$TEST_AWS_OBJECT" "$6/products/test.bin"
        ;;
      s3://breakapp-ticket-images/) mkdir -p "$6" ;;
      *) exit 17 ;;
    esac
    ;;
  *) echo 'unexpected mock AWS invocation' >&2;exit 18 ;;
esac
MOCK
chmod 700 "$temp/mockbin/aws"
export PATH="$temp/mockbin:$PATH"
export TEST_AWS_OBJECT="$temp/object.bin"
export SUPABASE_STORAGE_S3_ENDPOINT='https://ynvswdyirngvdpudcikl.storage.supabase.co/storage/v1/s3'
export SUPABASE_STORAGE_S3_REGION='eu-west-1'
export AWS_ACCESS_KEY_ID='fake-id-for-unit-test'
export AWS_SECRET_ACCESS_KEY='fake-secret-for-unit-test'
export BACKUP_PASSPHRASE='synthetic-archive-passphrase-over-32-characters'
bash scripts/backup-storage-s3.sh "$temp/out"
shopt -s nullglob
archives=("$temp/out"/*.tar.gpg)
[ "${#archives[@]}" -eq 1 ] || { echo 'S3 snapshot was not archived' >&2;exit 1; }
manifest="$(gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
  --decrypt "${archives[0]}" 3< <(printf '%s' "$BACKUP_PASSPHRASE") \
  | tar -xOf - './snapshot-manifest.json')"
printf '%s' "$manifest" | python3 -c '
import json,sys
m=json.load(sys.stdin)
assert m["format"]=="breakapp-storage-snapshot-v1"
assert len(m["buckets"])==2
assert m["total_objects"]==1
assert len(m["buckets"][0]["objects"])==1
assert m["buckets"][0]["objects"][0]["key"]=="products/test.bin"
print("Complete multi-bucket fake S3 snapshot and encrypted manifest verified")
'
 "$AWS_CONFIG_FILE" || exit 21
  printf 'classic\n'
  exit 0
fi
case "${3-} ${4-}" in
  's3api list-buckets')
    printf '%s\n' '{"Buckets":[{"Name":"breakapp-product-images"},{"Name":"breakapp-ticket-images"}]}'
    ;;
  's3api list-objects-v2')
    bucket=''
    while [ "$#" -gt 0 ]; do
      if [ "$1" = '--bucket' ]; then bucket="$2";break; fi
      shift
    done
    case "$bucket" in
      breakapp-product-images)
        size="$(wc -c < "$TEST_AWS_OBJECT" | tr -d ' ')"
        printf '{"Contents":[{"Key":"products/test.bin","Size":%s}]}\n' "$size"
        ;;
      breakapp-ticket-images) printf '%s\n' '{"Contents":[]}' ;;
      *) exit 16 ;;
    esac
    ;;
  's3 sync')
    case "${5-}" in
      s3://breakapp-product-images/)
        mkdir -p "$6/products"
        cp "$TEST_AWS_OBJECT" "$6/products/test.bin"
        ;;
      s3://breakapp-ticket-images/) mkdir -p "$6" ;;
      *) exit 17 ;;
    esac
    ;;
  *) echo 'unexpected mock AWS invocation' >&2;exit 18 ;;
esac
MOCK
chmod 700 "$temp/mockbin/aws"
export PATH="$temp/mockbin:$PATH"
export TEST_AWS_OBJECT="$temp/object.bin"
export SUPABASE_STORAGE_S3_ENDPOINT='https://ynvswdyirngvdpudcikl.storage.supabase.co/storage/v1/s3'
export SUPABASE_STORAGE_S3_REGION='eu-west-1'
export AWS_ACCESS_KEY_ID='fake-id-for-unit-test'
export AWS_SECRET_ACCESS_KEY='fake-secret-for-unit-test'
export BACKUP_PASSPHRASE='synthetic-archive-passphrase-over-32-characters'
bash scripts/backup-storage-s3.sh "$temp/out"
shopt -s nullglob
archives=("$temp/out"/*.tar.gpg)
[ "${#archives[@]}" -eq 1 ] || { echo 'S3 snapshot was not archived' >&2;exit 1; }
manifest="$(gpg --batch --yes --pinentry-mode loopback --passphrase-fd 3 \
  --decrypt "${archives[0]}" 3< <(printf '%s' "$BACKUP_PASSPHRASE") \
  | tar -xOf - './snapshot-manifest.json')"
printf '%s' "$manifest" | python3 -c '
import json,sys
m=json.load(sys.stdin)
assert m["format"]=="breakapp-storage-snapshot-v1"
assert len(m["buckets"])==2
assert m["total_objects"]==1
assert len(m["buckets"][0]["objects"])==1
assert m["buckets"][0]["objects"][0]["key"]=="products/test.bin"
print("Complete multi-bucket fake S3 snapshot and encrypted manifest verified")
'
