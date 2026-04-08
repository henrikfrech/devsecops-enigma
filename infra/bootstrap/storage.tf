resource "google_storage_bucket" "backup" {
  name          = local.bucket_name
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  logging {
    log_bucket        = google_storage_bucket.backup_access_logs.name
    log_object_prefix = "access-logs"
  }

  lifecycle_rule {
    condition { age = var.retention_days }
    action { type = "Delete" }
  }
}

resource "google_storage_bucket" "backup_access_logs" {
  # nosemgrep: terraform.gcp.security.gcp-cloud-storage-logging.gcp-cloud-storage-logging
  # Rationale: this is the dedicated log sink bucket; logging on this bucket would create recursive/chained logging.
  name          = "${local.bucket_name}-logs"
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_member" "public_read" {
  # trivy:ignore:GCP-0001
  # Rationale: Intentional for exercise: public object read is required to demonstrate storage exposure.
  bucket = google_storage_bucket.backup.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_storage_bucket_iam_member" "public_list" {
  # trivy:ignore:GCP-0001
  # Rationale: Intentional for exercise: public listing is required for the misconfiguration scenario.
  bucket = google_storage_bucket.backup.name
  role   = "roles/storage.legacyBucketReader"
  member = "allUsers"
}
