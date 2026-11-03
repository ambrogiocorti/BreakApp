#!/usr/bin/env bash
# Read-only Supabase Storage S3 snapshot: list every bucket, download every object,
# verify keys/sizes/hashes, then encrypt using the same passphrase as PostgreSQL.
set -euo pipefail
umask 077
: "${SUPABASE_STORAGE_S3_ENDPOINT:?Configure the S3 endpoint from Supabase Storage settings}"
: "${SUPABASE_STORAGE_S3_REGION:?Configure the Supabase S3 region}"
: "${AWS_ACCESS_KEY_ID:?Configure the S3 access key in GitHub Secrets}"
: "${AWS_SECRET_ACCESS_KEY:?Configure the S3 secret in GitHub Secrets}"
: "${BACKUP_PASSPHRASE:?Configure BACKUP_PASSPHRASE in GitHub Secrets}"
case "$SUPABASE_STORAGE_S3_ENDPOINT" in
  https://*.supabase.co/storage/v1/s3) ;;
  *) echo 'Unexpected S3 endpoint; copy the official HTTPS Supabase Storage S3 endpoint.' >&2; exit 1;;
esac
if ! [[ "$SUPABASE_STORAGE_S3_REGION" =~ ^[a-z]{2}-[a-z]+-[0-9]+$ ]]; then
  echo 'Invalid S3 region.' >&2; exit 1
fi
for cmd in aws python3 jq gpg tar sha256sum; do
  command -v "$cmd" >/dev/null || { echo "Missing required tool: $cmd" >&2; exit 1; }
done
destination="${1:?Pass output directory for encrypted archive}"
max_bytes="${BREAKAPP_STORAGE_BACKUP_MAX_BYTES:-1073741824}"  # 1 GiB fail-closed cap.
[[ "$max_bytes" =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid snapshot limit.' >&2; exit 1; }
workspace="$(mktemp -d)"
trap 'rm -rf "$workspace"' EXIT
mkdir -p "$workspace/buckets" "$workspace/listings" "$destination"
export AWS_DEFAULT_REGION="$SUPABASE_STORAGE_S3_REGION"
export AWS_EC2_METADATA_DISABLED=true AWS_CLI_AUTO_PROMPT=off
# AWS CLI >= 2.37 can select its CRT native transfer client automatically.
# On this Supabase S3 gateway, the observed 2026-11-03 GetObject of a key
# containing spaces was rejected with HTTP 403 SignatureDoesNotMatch, even
# though ListBuckets and ListObjectsV2 succeeded. Use the classic botocore
# transfer client for s3 sync: it performs SigV4 path canonicalization using
# the same stack as s3api. Isolate this configuration to this job only.
# A temporary AWS config does not contain credentials and is deleted by trap.
aws_config="$workspace/aws-config"
printf '[default]\nregion = %s\ns3 =\n    preferred_transfer_client = classic\n    addressing_style = path\n' "$SUPABASE_STORAGE_S3_REGION" > "$aws_config"
chmod 600 "$aws_config"
export AWS_CONFIG_FILE="$aws_config"
actual_client="$(aws configure get s3.preferred_transfer_client || true)"
if [ "$actual_client" != classic ]; then
  echo 'AWS CLI did not select the classic S3 transfer client; aborting unsafe backup.' >&2
  exit 1
fi
echo 'Supabase S3 download client: classic (SigV4 path-style).'
endpoint="$SUPABASE_STORAGE_S3_ENDPOINT"

aws --endpoint-url "$endpoint" s3api list-buckets --output json > "$workspace/bucket-list.json"
python3 - "$workspace" <<'PY'
import json,re,sys
from pathlib import Path
root=Path(sys.argv[1])
buckets=json.loads((root/'bucket-list.json').read_text(encoding='utf-8')).get('Buckets',[])
if not isinstance(buckets,list):raise SystemExit('Invalid bucket listing')
names=[]
for item in buckets:
    name=item.get('Name','')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{1,80}',name) or name in ('.','..'):
        raise SystemExit('Unsafe Storage bucket name: backup aborted')
    if name in names:raise SystemExit('Duplicate Storage bucket')
    names.append(name)
(root/'bucket-names.txt').write_text(''.join(n+'\n' for n in names),encoding='utf-8')
print('Storage buckets detected:',len(names))
PY
while IFS= read -r bucket; do
  [ -n "$bucket" ] || continue
  aws --endpoint-url "$endpoint" s3api list-objects-v2 \
    --bucket "$bucket" --output json > "$workspace/listings/$bucket.json"
  mkdir -p "$workspace/buckets/$bucket"
  aws --endpoint-url "$endpoint" s3 sync "s3://$bucket/" \
    "$workspace/buckets/$bucket/" --no-progress --only-show-errors
done < "$workspace/bucket-names.txt"

# Compare every downloaded object with the provider snapshot. Do not upload
# partial copies: an unexpected name, size or new/missing file aborts the run.
python3 - "$workspace" "$max_bytes" <<'PY'
import hashlib,json,sys
from pathlib import Path
root=Path(sys.argv[1]); limit=int(sys.argv[2])
names=(root/'bucket-names.txt').read_text(encoding='utf-8').splitlines()
total=0; manifest={'format':'breakapp-storage-snapshot-v1','buckets':[]}
for bucket in names:
    source=json.loads((root/'listings'/f'{bucket}.json').read_text(encoding='utf-8'))
    objects=source.get('Contents',[]) or []
    if not isinstance(objects,list):raise SystemExit('Invalid object list')
    expected={}
    for row in objects:
        key=row.get('Key')
        if not isinstance(key,str):raise SystemExit('Missing Storage object key')
        parts=key.split('/')
        if any(p in ('','.','..') for p in parts) or '\\' in key or '\x00' in key:
            raise SystemExit('Unsafe object key: backup aborted')
        if key in expected:raise SystemExit('Duplicate object key')
        size=row.get('Size')
        if not isinstance(size,int) or size<0:raise SystemExit('Invalid object size')
        expected[key]=size
        total+=size
        if total>limit:raise SystemExit('Storage backup exceeds the configured byte limit')
    folder=root/'buckets'/bucket
    actual={}
    for item in folder.rglob('*'):
        if item.is_symlink():raise SystemExit('Unexpected symlink in Storage snapshot')
        if not item.is_file():continue
        key=item.relative_to(folder).as_posix()
        actual[key]=item
    if set(actual)!=set(expected):raise SystemExit('Storage snapshot has missing or extra objects')
    files=[]
    for key,path in sorted(actual.items()):
        if path.stat().st_size!=expected[key]:raise SystemExit('Storage object size mismatch')
        h=hashlib.sha256()
        with path.open('rb') as stream:
            for chunk in iter(lambda:stream.read(1048576),b''):h.update(chunk)
        files.append({'key':key,'bytes':expected[key],'sha256':h.hexdigest()})
    manifest['buckets'].append({'name':bucket,'objects':files})
manifest['total_bytes']=total
manifest['total_objects']=sum(len(b['objects']) for b in manifest['buckets'])
(root/'snapshot-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Storage snapshot checked:',manifest['total_objects'],'objects,',total,'bytes')
PY

bash "$(dirname "$0")/create-encrypted-storage-archive.sh" "$workspace" "$destination"
