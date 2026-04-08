resource "google_container_cluster" "gke" {
  name     = var.cluster_name
  location = var.zone

  depends_on = [google_project_service.services]
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = false

  ip_allocation_policy {
    cluster_secondary_range_name  = "${var.subnet_name}-pods"
    services_secondary_range_name = "${var.subnet_name}-services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  release_channel {
    channel = "REGULAR"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  # trivy:ignore:GCP-0053
  # Intentional for exercise: control plane CIDR is open to demonstrate attack surface findings.
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "open-for-demo"
    }
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "primary-node-pool"
  cluster    = google_container_cluster.gke.name
  location   = var.zone
  node_count = 1

  node_config {
    machine_type    = "e2-medium"
    disk_type       = "pd-standard"
    disk_size_gb    = 30
    service_account = "default"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # trivy:ignore:GCP-0048
    # Intentional for exercise: legacy metadata endpoint remains enabled to demonstrate hardening gaps.
    metadata = {
      disable-legacy-endpoints = "false"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
