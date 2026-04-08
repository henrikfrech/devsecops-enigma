#!/usr/bin/env bash
set -euo pipefail

ARCH=$(dpkg --print-architecture)
echo "[setup] Detected architecture: $ARCH"

# Normalize arch names
if [[ "$ARCH" == "amd64" ]]; then
  TF_ARCH="amd64"
  MONGO_ARCH="x64"
else
  TF_ARCH="arm64"
  MONGO_ARCH="arm64"
fi

# ── Base packages ─────────────────────────────────────────────────────────────
echo "[setup] Installing base packages..."

apt-get update -qq
apt-get install -y --no-install-recommends \
  curl \
  jq \
  unzip \
  gettext-base \
  dnsutils \
  iputils-ping \
  netcat-openbsd \
  nmap \
  ca-certificates \
  gnupg \
  lsb-release \
  git \
  pre-commit \
  less

# ── Terraform (manual, stable) ────────────────────────────────────────────────
if ! command -v terraform &>/dev/null; then
  echo "[setup] Installing Terraform..."

  TF_VERSION="1.7.5"

  curl -fsSL \
    "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${TF_ARCH}.zip" \
    -o terraform.zip

  unzip terraform.zip
  mv terraform /usr/local/bin/
  rm terraform.zip
fi

# ── gcloud CLI ────────────────────────────────────────────────────────────────
if ! command -v gcloud &>/dev/null; then
  echo "[setup] Installing gcloud CLI..."

  mkdir -p /usr/share/keyrings

  if [[ ! -f /usr/share/keyrings/cloud.google.gpg ]]; then
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
      | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
  fi

  echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list

  apt-get update -qq
  apt-get install -y --no-install-recommends \
    google-cloud-cli \
    google-cloud-cli-gke-gcloud-auth-plugin
fi

# ── just ──────────────────────────────────────────────────────────────────────
if ! command -v just &>/dev/null; then
  echo "[setup] Installing just..."
  curl -fsSL https://just.systems/install.sh | bash -s -- --to /usr/local/bin
fi

# ── mongosh ───────────────────────────────────────────────────────────────────
if ! command -v mongosh &>/dev/null; then
  echo "[setup] Installing mongosh..."

  MONGOSH_VERSION="2.2.15"
  TARBALL="mongosh-${MONGOSH_VERSION}-linux-${MONGO_ARCH}.tgz"

  curl -fsSL "https://downloads.mongodb.com/compass/${TARBALL}" -o mongosh.tgz

  tar -xzf mongosh.tgz
  cp mongosh-*/bin/mongosh /usr/local/bin/

  chmod +x /usr/local/bin/mongosh
  rm -rf mongosh*
fi

# ── k9s (terminal UI for Kubernetes) ─────────────────────────────────────────
if ! command -v k9s &>/dev/null; then
  echo "[setup] Installing k9s..."
  K9S_VERSION=$(curl -fsSL https://api.github.com/repos/derailed/k9s/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
  if [ "$ARCH" = "amd64" ]; then K9S_ARCH="amd64"; else K9S_ARCH="arm64"; fi
  curl -fsSL "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${K9S_ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin k9s
  chmod +x /usr/local/bin/k9s
fi

# ── kubens + kubectx (fast namespace/context switching) ───────────────────────
if ! command -v kubens &>/dev/null; then
  echo "[setup] Installing kubens/kubectx..."
  KUBECTX_VERSION=$(curl -fsSL https://api.github.com/repos/ahmetb/kubectx/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)
  curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubens_${KUBECTX_VERSION}_linux_${ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin kubens
  curl -fsSL "https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubectx_${KUBECTX_VERSION}_linux_${ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin kubectx
fi

# ── k alias for kubectl ───────────────────────────────────────────────────────
if ! grep -q "alias k=" /etc/bash.bashrc 2>/dev/null; then
  echo "alias k=kubectl" >> /etc/bash.bashrc
  echo 'complete -o default -F __start_kubectl k' >> /etc/bash.bashrc
fi

# ── Cleanup ───────────────────────────────────────────────────────────────────
apt-get clean
rm -rf /var/lib/apt/lists/*

# ── Verify ────────────────────────────────────────────────────────────────────
echo ""
echo "[setup] Installed tool versions:"

echo "  terraform : $(terraform version | head -1)"
echo "  gcloud    : $(gcloud version | head -1)"
echo "  kubectl   : $(kubectl version --client --short 2>/dev/null || true)"
echo "  helm      : $(helm version --short 2>/dev/null || true)"
echo "  just      : $(just --version)"
echo "  pre-commit: $(pre-commit --version)"
echo "  mongosh   : $(mongosh --version | head -1)"
echo "  jq        : $(jq --version)"
echo "  nmap      : $(nmap --version | head -1)"
echo "  envsubst  : $(envsubst --version 2>&1 | head -1)"

echo ""
echo "[setup] Complete 🚀"
