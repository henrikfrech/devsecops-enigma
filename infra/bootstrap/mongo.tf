resource "google_compute_firewall" "allow_ssh_public" {
  name    = "allow-ssh-public"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["mongo-vm"]
}

resource "google_compute_firewall" "allow_mongo_from_gke" {
  name    = "allow-mongo-from-gke"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["27017"]
  }

  source_ranges = [var.pods_cidr]
  target_tags   = ["mongo-vm"]
}

resource "google_compute_instance" "mongo_vm" {
  name         = var.mongo_vm_name
  machine_type = var.mongo_machine_type
  zone         = var.zone
  tags         = ["mongo-vm"]

  depends_on = [google_project_service.services]

  boot_disk {
    initialize_params {
      image = "ubuntu-2004-focal-v20240110"
      size  = 30
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    # trivy:ignore:GCP-0031
    # Intentional for exercise: VM is publicly reachable over SSH for attack-path demonstration.
    access_config {}
  }

  service_account {
    email  = google_service_account.mongo_vm.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = templatefile("${path.module}/scripts/mongo_setup.sh.tftpl", {
    mongo_username = var.mongo_username
    mongo_password = var.mongo_password
    mongo_db_name  = var.mongo_db_name
    bucket_name    = local.bucket_name
    retention_days = var.retention_days
  })

  metadata = {
    enable-oslogin = "FALSE"
  }
}
