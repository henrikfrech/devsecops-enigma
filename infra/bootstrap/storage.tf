resource "google_storage_bucket" "backup" {
  name          = local.bucket_name
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition { age = var.retention_days }
    action { type = "Delete" }
  }
}

resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.backup.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_storage_bucket_iam_member" "public_list" {
  bucket = google_storage_bucket.backup.name
  role   = "roles/storage.legacyBucketReader"
  member = "allUsers"
}
