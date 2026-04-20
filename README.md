# GCP GitOps Security Lab

## Overview

This project implements the Wiz technical exercise on Google Cloud Platform using:

- OpenTofu/Terraform for infrastructure provisioning
- Argo CD for GitOps-based Kubernetes deployment
- GitHub Actions for CI/CD automation

## Security Exercise Context

The environment intentionally contains insecure configurations required by the exercise so they can be identified, demonstrated, and discussed during the presentation.

## Validation

### Verify `wizexercise.txt`

```bash
kubectl exec -it <pod-name> -n wiz-app -- cat /app/wizexercise.txt
```

### Verify MongoDB persistence

1. Access the web application UI (via Ingress load balancer IP)
2. Create test data
3. Restart the pod: `kubectl rollout restart deployment/wiz-app -n wiz-app`
4. Confirm data persists after restart


## Architecture

### Components

**1. Web Application (GKE)**
- Containerized application deployed to a private GKE cluster
- Exposed publicly through Kubernetes Ingress and a cloud load balancer
- Uses MongoDB through an environment variable configured in Kubernetes

**2. Database (Compute Engine VM)**
- MongoDB running on an intentionally outdated Linux VM
- SSH exposed publicly as an intentional misconfiguration
- MongoDB access restricted to the Kubernetes network and protected with authentication

**3. Storage (GCS)**
- Automated daily MongoDB backups
- Backup bucket intentionally configured for public read and public listing

**4. GitOps (Argo CD)**
- Installed after cluster provisioning from the platform layer
- Deploys rendered Kubernetes manifests from Git
- Optional Google SSO via Dex/OIDC

**5. CI/CD (GitHub Actions)**
- One pipeline for infrastructure deployment
- One pipeline for application build, push, and GitOps update

---

## Repository Structure

```
.
├── infra/              # Terraform (GCP infrastructure)
├── app/                # Application + Dockerfile
├── gitops/             # Kubernetes manifests (Argo CD)
├── .github/workflows/  # CI/CD pipelines
├── .devcontainer/      # Dev environment (optional)
└── README.md
```

---

## DevContainer

This project includes a reproducible development environment.

### Requirements

* VS Code
* Dev Containers extension

### Usage

1. Open repo in VS Code
2. Click **"Reopen in Container"**

Preinstalled tools:

* Terraform
* kubectl
* gcloud CLI
* Helm

---

## Deployment Flow

### 1. Infrastructure (Terraform)

* VPC + subnets
* Private GKE cluster
* MongoDB VM
* GCS bucket
* IAM roles (intentionally permissive)
* Argo CD installation

### 2. Application (CI/CD)

* Build Docker image
* Scan container image
* Push to Artifact Registry
* Update GitOps manifests

### 3. GitOps (Argo CD)

* Sync Kubernetes resources
* Deploy application automatically

---

## Setup Instructions

### 1. Clone

```bash
git clone <repo-url>
cd devsecops-enigma
```

### 2. Authenticate with GCP

Recommended: Workload Identity Federation

Alternative:

```bash
gcloud auth application-default login
```

### 3. Bootstrap GCP Infrastructure

```bash
just bootstrap
```

This deploys VPC, GKE cluster, MongoDB VM, storage bucket, and IAM roles.

### 4. Deploy Argo CD and Application

```bash
just argo
```

This installs Argo CD and applies the Application manifest to sync GitOps-based deployments.

### 5. Access Argo CD UI

```bash
just argocd-forward
```

Then navigate to http://localhost:8080 (username: admin, password shown in terminal).

### 6. Access Application

```bash
kubectl get ingress -n wiz-app
```

Use the EXTERNAL-IP from the ingress to access the application.

---

## Manual GCP Operations (Knowledge Retention)

Use this section as a quick reference when you want to operate the environment manually without `just` commands.

### 1. Set project context

```bash
export GCP_PROJECT_ID="project-b4952354-c0d7-4e0a-a90"
export GCP_REGION="europe-west1"
export GCP_ZONE="europe-west1-b"

gcloud auth login
gcloud config set project "$GCP_PROJECT_ID"
gcloud auth application-default login


```

### 2. Enable required APIs

```bash
gcloud services enable \
	compute.googleapis.com \
	container.googleapis.com \
	artifactregistry.googleapis.com \
	cloudbuild.googleapis.com \
	storage.googleapis.com
```

### 3. Artifact Registry (container images)

Check repositories:

```bash
gcloud artifacts repositories list --location "$GCP_REGION"
```

Create repo (if missing):

```bash
gcloud artifacts repositories create wiz-app \
	--repository-format docker \
	--location "$GCP_REGION" \
	--description "Wiz app images"
```

List images/tags:

```bash
gcloud artifacts docker images list \
	"$GCP_REGION-docker.pkg.dev/$GCP_PROJECT_ID/wiz-app" \
	--include-tags
```

### 4. Build and push image manually

Preferred in this environment (no local Docker daemon required):

```bash
gcloud builds submit app \
	--tag "$GCP_REGION-docker.pkg.dev/$GCP_PROJECT_ID/wiz-app/app:latest" \
	--project "$GCP_PROJECT_ID"
```

If Docker is available locally:

```bash
gcloud auth configure-docker "$GCP_REGION-docker.pkg.dev"
docker build -t app-local:latest ./app
docker tag app-local:latest "$GCP_REGION-docker.pkg.dev/$GCP_PROJECT_ID/wiz-app/app:latest"
docker push "$GCP_REGION-docker.pkg.dev/$GCP_PROJECT_ID/wiz-app/app:latest"
```

### 5. GKE manual access and checks

Get cluster credentials:

```bash
gcloud container clusters get-credentials wiz-gke \
	--zone "$GCP_ZONE" \
	--project "$GCP_PROJECT_ID"
```

Verify cluster and workloads:

```bash
kubectl get nodes
kubectl get ns
kubectl -n wiz-app get deploy,svc,ingress,pods
kubectl -n argocd get application wiz-app
```

### 6. Argo CD manual operations

Force refresh and check sync/health:

```bash
kubectl -n argocd annotate application wiz-app argocd.argoproj.io/refresh=hard --overwrite
kubectl -n argocd get application wiz-app -o jsonpath='{.status.sync.status}{" | "}{.status.health.status}{"\n"}'
```

Port-forward Argo UI:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

### 7. VM manual operations (Mongo host)

SSH into the VM:

```bash
gcloud compute ssh mongo-vm --zone "$GCP_ZONE" --project "$GCP_PROJECT_ID"
```

On VM: validate MongoDB service and listener:

```bash
sudo systemctl status mongodb --no-pager
sudo ss -ltnp | grep 27017
```

On VM: verify app user login:

```bash
mongo admin -u appuser -p 'change-me' --authenticationDatabase admin --eval 'db.runCommand({ping:1})'
```

### 8. Storage and backups (GCS)

List backup bucket objects:

```bash
gcloud storage ls "gs://$GCP_PROJECT_ID-mongo-backups"
```

Check bucket IAM/public exposure:

```bash
gcloud storage buckets get-iam-policy "gs://$GCP_PROJECT_ID-mongo-backups"
```

### 9. Fast troubleshooting commands

Application logs:

```bash
kubectl -n wiz-app logs deploy/wiz-app --tail=200
```

Restart app rollout:

```bash
kubectl -n wiz-app rollout restart deployment wiz-app
kubectl -n wiz-app rollout status deployment wiz-app --timeout=180s
```

Connectivity from pod to Mongo:

```bash
POD=$(kubectl -n wiz-app get pods -l app=wiz-app -o jsonpath='{.items[0].metadata.name}')
kubectl -n wiz-app exec "$POD" -- nc -vz 10.0.0.26 27017
```

Rebuild image and redeploy in one flow:

```bash
gcloud builds submit app --tag "$GCP_REGION-docker.pkg.dev/$GCP_PROJECT_ID/wiz-app/app:latest"
kubectl -n wiz-app rollout restart deployment wiz-app
```

---

## Application Validation

### Verify container file

```bash
POD=$(kubectl get pod -n wiz-app -l app=wiz-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $POD -n wiz-app -- cat /app/wizexercise.txt
```

### Verify DB persistence

* Get app ingress IP: `kubectl get ingress -n wiz-app`
* Use that IP to access the web UI
* Create test data via the UI
* Restart pod: `kubectl rollout restart deployment/wiz-app -n wiz-app`
* Confirm data still exists after reload

---
## Security Alignment

This lab simulates common cloud risks:

- CIS: Public storage exposure
- OWASP: Sensitive data exposure
- Cloud IAM: Overprivileged roles
- Kubernetes: RBAC misconfiguration

## Security Misconfigurations (Intentional)

| Component  | Misconfiguration | Risk |
|------------|----------------|------|
| VM         | Outdated OS | Known CVEs exploitable |
| MongoDB    | Outdated version | Data compromise risk |
| Network    | SSH open | Brute force / lateral movement |
| IAM        | Overly permissive | Privilege escalation |
| Kubernetes | cluster-admin | Full cluster compromise |
| Storage    | Public bucket | Data exfiltration |

---

## Security Controls

### Preventative

* Terraform validation
* GitHub branch protection
* No static credentials (Workload Identity)

### Detective

* GCP Audit Logs
* CI/CD scanning (IaC + containers)
* Logging & monitoring alerts

## Security Monitoring

- GCP Audit Logs enabled
- Detect public bucket access
- Detect VM SSH access attempts

---

## CI/CD Pipelines

### Infra Pipeline (.github/workflows/infra.yaml)

* terraform fmt
* terraform validate
* Trivy IaC security scan
* terraform apply (infra/bootstrap)
* Render manifests (deployment, secret, ingress, argocd values)

### App Pipeline (.github/workflows/app.yaml)

* NPM audit (dependencies)
* Trivy filesystem scan
* Docker build
* Trivy container image scan
* Push to Artifact Registry
* Render app manifests

**Note:** Rendered manifests are stored in `gitops/rendered/` and deployed by Argo CD.


---

## Argo CD Authentication

* Google SSO via Dex (optional)
* RBAC support

---

## Demo Checklist

* Terraform provisioning
* Argo CD UI
* kubectl usage
* Web app working
* MongoDB data persistence
* Container file validation
* Security findings explanation

---

## GitOps Details

**Argo CD Application:** Points to rendered manifests for app, secrets, and ingress.

**Namespace:** All app resources (deployment, service, secret, ingress) are in the `wiz-app` namespace.

**Manifests Location:** `gitops/rendered/` (populated by CI/CD pipelines).

**Base Resources:** `gitops/base/` contains namespace, RBAC, and service templates.

**Templates:** `gitops/templates/` contains Jinja/envsubst templates for deployment, ingress, secret, and Argo CD values.

## Future Improvements

* Harden IAM roles
* Remove public access
* Upgrade OS/DB versions
* Add OPA / Gatekeeper
* Integrate Wiz CLI (if available)
* Implement daily backup scheduling via Cloud Scheduler
* Add detective security controls (Security Command Center, log alerts)

---

## Notes

This project is **intentionally insecure** and designed for a technical exercise.
Do NOT use in production.

---

## Author

Henrik Frech
