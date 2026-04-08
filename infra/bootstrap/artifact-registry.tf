resource "google_artifact_registry_repository" "docker_repo" {
  location      = var.region
  repository_id = "wiz-app"
  description   = "Docker repository for Wiz exercise app"
  format        = "DOCKER"

  depends_on = [google_project_service.services]
}
