set dotenv-load := true
set shell := ["bash", "-euo", "pipefail", "-c"]

bootstrap_dir := "infra/bootstrap"
bucket := env_var("GCP_PROJECT_ID") + "-tf-state"

# List all Just commands
default:
  @just --list

# Use GCP Login
auth:
  gcloud auth login
  gcloud auth application-default login
  gcloud config set project $GCP_PROJECT_ID

# Import all existing GCP resources back into Terraform state
import-bootstrap:
  terraform -chdir={{bootstrap_dir}} init

  terraform -chdir={{bootstrap_dir}} import \
    -var="project_id=$GCP_PROJECT_ID" -var="region=$GCP_REGION" \
    google_compute_network.vpc \
    projects/$GCP_PROJECT_ID/global/networks/wiz-vpc || true

  terraform -chdir={{bootstrap_dir}} import \
    -var="project_id=$GCP_PROJECT_ID" -var="region=$GCP_REGION" \
    google_compute_subnetwork.subnet \
    projects/$GCP_PROJECT_ID/regions/$GCP_REGION/subnetworks/wiz-subnet || true

  terraform -chdir={{bootstrap_dir}} import \
    -var="project_id=$GCP_PROJECT_ID" -var="region=$GCP_REGION" \
    google_compute_firewall.allow_ssh_public \
    projects/$GCP_PROJECT_ID/global/firewalls/allow-ssh-public || true

  terraform -chdir={{bootstrap_dir}} import \
    -var="project_id=$GCP_PROJECT_ID" -var="region=$GCP_REGION" \
    google_compute_firewall.allow_mongo_from_gke \
    projects/$GCP_PROJECT_ID/global/firewalls/allow-mongo-from-gke || true

  terraform -chdir={{bootstrap_dir}} import \
    -var="project_id=$GCP_PROJECT_ID" -var="region=$GCP_REGION" \
    google_service_account.mongo_vm \
    projects/$GCP_PROJECT_ID/serviceAccounts/mongo-vm-sa@$GCP_PROJECT_ID.iam.gserviceaccount.com || true

  terraform -chdir={{bootstrap_dir}} import \
    -var="project_id=$GCP_PROJECT_ID" -var="region=$GCP_REGION" \
    google_artifact_registry_repository.docker_repo \
    projects/$GCP_PROJECT_ID/locations/$GCP_REGION/repositories/wiz-app || true

  terraform -chdir={{bootstrap_dir}} import \
    -var="project_id=$GCP_PROJECT_ID" -var="region=$GCP_REGION" \
    google_storage_bucket.backup \
    $GCP_PROJECT_ID-mongo-backups || true

  terraform -chdir={{bootstrap_dir}} import \
    -var="project_id=$GCP_PROJECT_ID" -var="region=$GCP_REGION" \
    google_compute_instance.mongo_vm \
    projects/$GCP_PROJECT_ID/zones/$GCP_REGION-a/instances/mongo-vm || true

  terraform -chdir={{bootstrap_dir}} import \
    -var="project_id=$GCP_PROJECT_ID" -var="region=$GCP_REGION" \
    google_container_cluster.gke \
    projects/$GCP_PROJECT_ID/locations/$GCP_REGION-a/clusters/wiz-gke || true

  terraform -chdir={{bootstrap_dir}} import \
    -var="project_id=$GCP_PROJECT_ID" -var="region=$GCP_REGION" \
    google_container_node_pool.primary_nodes \
    projects/$GCP_PROJECT_ID/locations/$GCP_REGION-a/clusters/wiz-gke/nodePools/primary-node-pool || true

# Bootstrap GCP Infra
bootstrap:
  gcloud storage buckets describe gs://{{bucket}} \
    --project=$GCP_PROJECT_ID >/dev/null 2>&1 || \
  gcloud storage buckets create gs://{{bucket}} \
    --project=$GCP_PROJECT_ID \
    --location=$GCP_REGION \
    --uniform-bucket-level-access

  gcloud storage buckets update gs://{{bucket}} \
    --project=$GCP_PROJECT_ID \
    --versioning >/dev/null 2>&1 || true

  terraform -chdir={{bootstrap_dir}} init \
    -backend-config="bucket={{bucket}}"

  terraform -chdir={{bootstrap_dir}} apply -auto-approve \
    -var="project_id=$GCP_PROJECT_ID" \
    -var="region=$GCP_REGION"

# Delete all GCP resources
bootstrap-destroy:
  terraform -chdir={{bootstrap_dir}} destroy -auto-approve \
    -var="project_id=$GCP_PROJECT_ID" \
    -var="region=$GCP_REGION"

# Create ArgoCD and deploy App
argo:
  gcloud storage buckets describe gs://{{bucket}} \
    --project=$GCP_PROJECT_ID >/dev/null 2>&1 || \
  gcloud storage buckets create gs://{{bucket}} \
    --project=$GCP_PROJECT_ID \
    --location=$GCP_REGION \
    --uniform-bucket-level-access
  just render
  terraform -chdir={{bootstrap_dir}} output -raw cluster_name > /tmp/cluster_name
  gcloud container clusters get-credentials $(cat /tmp/cluster_name) \
    --zone=$GCP_REGION-a \
    --project=$GCP_PROJECT_ID
  helm repo add argo https://argoproj.github.io/argo-helm
  helm repo update
  if [[ -f gitops/rendered/argocd-values-secret.sops.yaml ]]; then \
    sops -d gitops/rendered/argocd-values-secret.sops.yaml > /tmp/argocd-values-secret.yaml; \
    helm upgrade --install argocd argo/argo-cd \
      -n argocd \
      --create-namespace \
      -f gitops/rendered/argocd-values.yaml \
      -f /tmp/argocd-values-secret.yaml \
      --timeout 15m \
      --wait; \
    rm -f /tmp/argocd-values-secret.yaml; \
  else \
    helm upgrade --install argocd argo/argo-cd \
      -n argocd \
      --create-namespace \
      -f gitops/rendered/argocd-values.yaml \
      --timeout 15m \
      --wait; \
  fi
  # Apply base resources (namespace, service account, rbac, service)
  kubectl apply -f gitops/rendered/namespace.yaml
  kubectl apply -f gitops/rendered/serviceaccount.yaml
  kubectl apply -f gitops/rendered/rbac.yaml
  kubectl apply -f gitops/rendered/service.yaml
  # Apply Argo Application
  kubectl apply -f gitops/app.yaml

# Forward Argo CD (https://localhost:8080) and app (http://localhost:3000)
forward:
  @echo "Argo CD: http://localhost:8080"
  @echo "Wiz App: http://localhost:3000"
  @echo "Username: admin"
  @kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath='{.data.password}' | base64 -d | xargs -I{} echo "Password: {}"
  kubectl -n argocd port-forward svc/argocd-server 8080:80 &
  POD=$(kubectl -n wiz-app get pod -l app=wiz-app -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | awk '{print $1}'); [[ -n "$POD" ]] || { echo "No running pod found in wiz-app namespace"; exit 1; }; kubectl -n wiz-app port-forward pod/$POD 3000:3000

# Destroy ArgoCD and GKE cluster
argo-destroy:
  terraform -chdir={{bootstrap_dir}} output -raw cluster_name > /tmp/cluster_name
  gcloud container clusters get-credentials $(cat /tmp/cluster_name) \
    --zone=$GCP_REGION-a \
    --project=$GCP_PROJECT_ID
  helm uninstall argocd -n argocd || true
  kubectl delete namespace argocd || true

# Render the Kubernetes manifests with environment variables
render:
  mkdir -p gitops/rendered
  # Copy base resources (namespace, service account, rbac, service)
  cp gitops/base/namespace.yaml gitops/rendered/
  cp gitops/base/serviceaccount.yaml gitops/rendered/
  cp gitops/base/rbac.yaml gitops/rendered/
  cp gitops/base/service.yaml gitops/rendered/
  terraform -chdir={{bootstrap_dir}} output -raw mongo_private_ip > /tmp/mongo_ip
  MONGO_PRIVATE_IP=$(cat /tmp/mongo_ip) \
  DOMAIN="${APP_DOMAIN:-}" \
  IMAGE="$GCP_REGION-docker.pkg.dev/$GCP_PROJECT_ID/wiz-app/app:latest" \
  MONGO_USERNAME="$MONGO_USERNAME" \
  MONGO_PASSWORD="$MONGO_PASSWORD" \
  MONGO_DB="$MONGO_DB" \
  ARGOCD_DOMAIN="$(echo "${ARGOCD_HOSTNAME:-argocd.local}" | sed -E 's#^https?://##; s#/.*$##')" \
  ARGOCD_URL="$(h="${ARGOCD_HOSTNAME:-argocd.local}"; if [[ "$h" == http://* || "$h" == https://* ]]; then echo "${h%/}"; else echo "https://$h"; fi)" \
  GOOGLE_OIDC_CLIENT_ID="${GOOGLE_OIDC_CLIENT_ID:-}" \
  GOOGLE_OIDC_CLIENT_SECRET="${GOOGLE_OIDC_CLIENT_SECRET:-}" \
  GOOGLE_WORKSPACE_DOMAIN="${GOOGLE_WORKSPACE_DOMAIN:-}" \
  ARGOCD_ADMIN_GROUP="${ARGOCD_ADMIN_GROUP:-}" \
  DEX_CLIENT_SECRET_REF='$dex.google.clientSecret' \
  bash -c ' \
    envsubst < gitops/templates/deployment.yaml.tpl > gitops/rendered/deployment.yaml && \
    envsubst < gitops/templates/ingress.yaml.tpl > gitops/rendered/ingress.yaml && \
    envsubst < gitops/templates/secret.yaml.tpl > gitops/rendered/secret.yaml && \
    envsubst < gitops/templates/values.yaml.tpl > gitops/rendered/argocd-values.yaml && \
    if [[ -n "${SOPS_AGE_RECIPIENT:-}" ]] && command -v sops >/dev/null 2>&1; then \
      envsubst < gitops/templates/values-secret.yaml.tpl > /tmp/argocd-values-secret.yaml && \
      sops --encrypt --age "${SOPS_AGE_RECIPIENT}" /tmp/argocd-values-secret.yaml > gitops/rendered/argocd-values-secret.sops.yaml && \
      rm -f /tmp/argocd-values-secret.yaml; \
    else \
      echo "[render] Skipping encrypted Argo secret values (set SOPS_AGE_RECIPIENT and install sops)."; \
    fi && \
    echo "Rendered manifests written to gitops/rendered/"'
