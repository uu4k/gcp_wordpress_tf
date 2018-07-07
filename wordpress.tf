terraform {
  backend "gcs" {
    bucket  = "uu4k-me-wordpress"
    path    = "terraform/wordpress/terraform.tfstate"
    project = "wordpress-194820"
  }
}

provider "google" {
  project = "wordpress-194820"
  region  = "us-central1"
}

resource "google_compute_address" "wordpress-address" {
  name   = "wordpress-address"
  region = "us-central1"
}

resource "google_compute_disk" "wordpress-db" {
  name = "wordpress-db"
  type = "pd-standard"
  zone = "us-central1-c"
  size = 10
}

resource "google_compute_instance" "wordpress" {
  name         = "wordpress"
  zone         = "us-central1-c"
  machine_type = "f1-micro"
  tags         = ["http-server", "https-server"]
  depends_on   = ["google_compute_address.wordpress-address", "google_compute_disk.wordpress-db"]

  metadata {
    user-data = "${local.CLOUD_INIT_CONFIG}"
  }

  boot_disk {
    initialize_params {
      image = "cos-cloud/cos-stable"
      type  = "pd-standard"
      size  = 10
    }
  }

  attached_disk {
    source = "${google_compute_disk.wordpress-db.self_link}"
  }

  service_account {
    scopes = ["logging-write", "monitoring", "sql", "sql-admin", "storage-rw", "compute-rw", "https://www.googleapis.com/auth/source.read_write"]
  }

  network_interface {
    network = "default"

    access_config {
      nat_ip = "${google_compute_address.wordpress-address.address}"
    }
  }

  lifecycle {
    ignore_changes = [
      "machine_type",
      "boot_disk",
      "network_interface",
    ]
  }
}
