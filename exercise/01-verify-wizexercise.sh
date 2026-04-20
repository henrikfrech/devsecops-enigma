#!/usr/bin/env bash
set -euo pipefail

POD_NAME=$(kubectl -n wiz-app get pod -l app=wiz-app -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | awk '{print $1}')

if [[ -z "$POD_NAME" ]]; then
  echo "No running wiz-app pod found in namespace wiz-app"
  exit 1
fi

WIZEXERCISE_CONTENT=$(kubectl -n wiz-app exec "$POD_NAME" -- cat /app/wizexercise.txt 2>/dev/null || true)

if [[ -z "$WIZEXERCISE_CONTENT" ]]; then
  echo "FAIL: /app/wizexercise.txt is missing or empty in pod $POD_NAME"
  exit 1
fi

echo "PASS: /app/wizexercise.txt found in pod $POD_NAME"
echo "$WIZEXERCISE_CONTENT"
