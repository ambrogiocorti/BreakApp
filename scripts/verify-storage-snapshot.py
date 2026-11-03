#!/usr/bin/env python3
"""Recover the encrypted Storage archive as a read-only stream and verify every byte.

No plaintext file is written. A successful exit means that all archived Storage
object bytes agree with the SHA-256 manifest stored inside the same archive.
It does not validate S3 upload or restoration of Supabase access policies.
"""
import hashlib
import json
import os
import posixpath
import subprocess
import sys
import tarfile

MAX_BYTES = 1_073_741_824
MAX_MANIFEST_BYTES = 16 * 1024 * 1024
MAX_OBJECTS = 100_000


def fail(message):
    raise ValueError(message)


def verify_archive(archive):
    passphrase = os.environ.get("BACKUP_PASSPHRASE", "")
    if len(passphrase) < 32:
        fail("BACKUP_PASSPHRASE non configurata (minimo 32 caratteri).")
    if not os.path.isfile(archive):
        fail("Archivio Storage inesistente.")

    process = subprocess.Popen(
        ["gpg", "--batch", "--yes", "--no-tty", "--pinentry-mode", "loopback",
         "--passphrase-fd", "0", "--decrypt", archive],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    objects = {}
    manifest_bytes = None
    total_bytes = 0
    try:
        process.stdin.write(passphrase.encode("utf-8") + b"\n")
        process.stdin.close()

        with tarfile.open(fileobj=process.stdout, mode="r|") as stream:
            names = set()
            for item in stream:
                raw = item.name
                if raw in (".", "./"):
                    if not item.isdir():
                        fail("Invalid root tar entry")
                    continue
                if raw.startswith("/") or "\x00" in raw or "\\" in raw:
                    fail("Unsafe archive path")
                path = raw.removeprefix("./")
                segments = path.split("/")
                if any(segment in ("", ".", "..") for segment in segments):
                    fail("Unsafe archive path segment")
                normalized = posixpath.normpath(path)
                if normalized != path:
                    fail("Non-canonical archive path")
                if item.isdir():
                    continue
                if not item.isfile():
                    fail("Links and special files are forbidden in Storage backups")
                if path in names:
                    fail("Duplicate archive entry")
                names.add(path)
                if item.size < 0:
                    fail("Invalid archive entry size")

                if path.startswith("buckets/"):
                    segments = path.split("/", 2)
                    if len(segments) != 3 or not segments[1] or not segments[2]:
                        fail("Invalid Storage object archive path")
                    if len(objects) >= MAX_OBJECTS:
                        fail("Storage snapshot exceeds object safety limit")
                    total_bytes += item.size
                    if total_bytes > MAX_BYTES:
                        fail("Storage snapshot exceeds byte safety limit")

                    streamfile = stream.extractfile(item)
                    if streamfile is None:
                        fail("Archived Storage object cannot be recovered")
                    digest = hashlib.sha256()
                    count = 0
                    for chunk in iter(lambda: streamfile.read(1024 * 1024), b""):
                        digest.update(chunk)
                        count += len(chunk)
                    if count != item.size:
                        fail("Recovered Storage bytes do not match tar entry")
                    objects[(segments[1], segments[2])] = (count, digest.hexdigest())
                elif path == "snapshot-manifest.json":
                    if item.size > MAX_MANIFEST_BYTES:
                        fail("Storage manifest too large")
                    manifest_bytes = stream.extractfile(item).read()
                elif path in ("bucket-list.json", "bucket-names.txt") or path.startswith("listings/"):
                    if item.size > MAX_MANIFEST_BYTES:
                        fail("Storage metadata file too large")
                    # Read the content to prove that every tar entry is readable.
                    stream.extractfile(item).read()
                else:
                    fail("Unexpected file in Storage snapshot")
        process.stdout.close()
        stderr = process.stderr.read()
        rc = process.wait()
        if rc != 0:
            fail("GPG could not authenticate/decrypt the Storage archive")
    except BaseException:
        if process.poll() is None:
            process.kill()
        process.wait()
        raise
    finally:
        if process.stdout and not process.stdout.closed:
            process.stdout.close()
        if process.stderr and not process.stderr.closed:
            process.stderr.close()

    if manifest_bytes is None:
        fail("Storage manifest missing from encrypted archive")
    manifest = json.loads(manifest_bytes)
    if manifest.get("format") != "breakapp-storage-snapshot-v1":
        fail("Unsupported Storage snapshot manifest")
    buckets = manifest.get("buckets")
    if not isinstance(buckets, list):
        fail("Invalid Storage bucket list")
    expected = {}
    seen_buckets = set()
    for bucket in buckets:
        name = bucket.get("name")
        if not isinstance(name, str) or name in seen_buckets:
            fail("Duplicate or invalid bucket in manifest")
        seen_buckets.add(name)
        entries = bucket.get("objects")
        if not isinstance(entries, list):
            fail("Invalid Storage bucket contents in manifest")
        for entry in entries:
            key = (name, entry.get("key"))
            if not isinstance(key[1], str) or key in expected:
                fail("Duplicate or invalid object in manifest")
            length, sha = entry.get("bytes"), entry.get("sha256")
            if not isinstance(length, int) or length < 0:
                fail("Invalid object length in manifest")
            if not isinstance(sha, str) or len(sha) != 64:
                fail("Invalid object checksum in manifest")
            expected[key] = (length, sha)

    if expected != objects:
        fail("Restored file bytes do not match the Storage snapshot manifest")
    if manifest.get("total_objects") != len(objects):
        fail("Storage object count mismatch")
    if manifest.get("total_bytes") != total_bytes:
        fail("Storage byte count mismatch")
    print(f"[OK] Recuperati e verificati {len(objects)} oggetti Storage, "
          f"{total_bytes} byte, {len(seen_buckets)} bucket (SHA-256).")
    print("[INFO] Solo lettura: nessun file in chiaro conservato sul runner.")


def main():
    if len(sys.argv) != 2:
        print("Usage: BACKUP_PASSPHRASE=... python3 "
              "scripts/verify-storage-snapshot.py <archive.tar.gpg>", file=sys.stderr)
        return 2
    try:
        verify_archive(sys.argv[1])
    except (ValueError, OSError, json.JSONDecodeError, tarfile.TarError,
            BrokenPipeError) as error:
        print(f"[NO] Verifica recupero Storage fallita: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
