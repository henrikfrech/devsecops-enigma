resource "google_service_account" "mongo_vm" {
  account_id   = "mongo-vm-sa"
  display_name = "Mongo VM Service Account"
}

resource "google_project_iam_member" "mongo_vm_compute_admin" {
  project = var.project_id
  role    = "roles/compute.admin"
  member  = "serviceAccount:${google_service_account.mongo_vm.email}"
}

resource "google_project_iam_member" "mongo_vm_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.mongo_vm.email}"
}

resource "google_project_service" "services" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "dns.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "storage.googleapis.com"
  ])

  service            = each.value
  disable_on_destroy = false
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_project_iam_member" "gke_node_artifactregistry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${data.google_project.current.number}-compute@developer.gserviceaccount.com"
}
