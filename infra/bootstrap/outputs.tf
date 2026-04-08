output "cluster_name" {
  value = google_container_cluster.gke.name
}

output "cluster_region" {
  value = var.region
}

output "mongo_public_ip" {
  value = google_compute_instance.mongo_vm.network_interface[0].access_config[0].nat_ip
}

output "mongo_private_ip" {
  value = google_compute_instance.mongo_vm.network_interface[0].network_ip
}

output "backup_bucket_name" {
  value = google_storage_bucket.backup.name
}

output "artifact_registry_repo" {
  value = google_artifact_registry_repository.docker_repo.name
}
