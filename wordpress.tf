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
  name  = "wordpress-db"
  type  = "pd-standard"
  zone  = "us-central1-c"
  size  = 10
}

variable "ROOT_DB_PASSWORD" {
  default = "password"
}

variable "WORDPRESS_DB_PASSWORD" {
  default = "password"
}

resource "google_compute_instance" "wordpress" {
  name         = "wordpress"
  zone         = "us-central1-c"
  machine_type = "f1-micro"
  tags         = ["http-server", "https-server"]
  depends_on   = ["google_compute_address.wordpress-address", "google_compute_disk.wordpress-db"]

  metadata {
    ROOT_DB_PASSWORD      = "${var.ROOT_DB_PASSWORD}"
    WORDPRESS_DB_PASSWORD = "${var.WORDPRESS_DB_PASSWORD}"
  }
  
  metadata_startup_script = <<EOF
mkdir -p /mnt/disks/wordpress-db
mount -o discard,defaults /dev/sdb /mnt/disks/wordpress-db

if [ $? != 0 ]; then
  mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0,discard /dev/sdb 
  mount -o discard,defaults /dev/sdb /mnt/disks/wordpress-db
fi

export ZONE=$$(basename $$(curl "http://metadata.google.internal/computeMetadata/v1/instance/zone" -H "Metadata-Flavor: Google"))
export ROOT_DB_PASSWORD=$$(curl "http://metadata.google.internal/computeMetadata/v1/instance/attributes/ROOT_DB_PASSWORD" -H "Metadata-Flavor: Google")
export WORDPRESS_DB_PASSWORD=$$(curl "http://metadata.google.internal/computeMetadata/v1/instance/attributes/WORDPRESS_DB_PASSWORD" -H "Metadata-Flavor: Google")

echo '
version: "3"

services:
  db:
    image: mysql:5.7
    volumes:
      - /mnt/disks/wordpress-db/mysql:/var/lib/mysql
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: $${ROOT_DB_PASSWORD}
      MYSQL_DATABASE: wordpress
      MYSQL_USER: wordpress
      MYSQL_PASSWORD: $${WORDPRESS_DB_PASSWORD}

  wordpress:
    depends_on:
      - db
    image: wordpress:latest
    ports:
      - "80:80"
      - "443:443"
    restart: always
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: wordpress
      WORDPRESS_DB_PASSWORD: $${WORDPRESS_DB_PASSWORD}
' > /tmp/docker-compose.yml

docker run \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "/mnt/disks/wordpress-db:/mnt/disks/wordpress-db" \
    -v "/tmp/docker-compose.yml:/tmp/docker-compose.yml" \
    -v "$PWD:/rootfs/$PWD" \
    -w="/rootfs/$PWD" \
    -e="ROOT_DB_PASSWORD=$${ROOT_DB_PASSWORD}" \
    -e="WORDPRESS_DB_PASSWORD=$${WORDPRESS_DB_PASSWORD}" \
    docker/compose:1.19.0 -f /tmp/docker-compose.yml up -d
EOF

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
      "network_interface"
    ]
  }
}