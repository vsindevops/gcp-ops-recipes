# instances: bastion & prod server
# Fetch Ubuntu 22.04 LTS image
data "google_compute_image" "ubuntu_2204" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

# Bastion (public IP, small)
resource "google_compute_instance" "bastion" {
  name         = "bastion"
  machine_type = "e2-custom-1-2048"      # 1 vCPU, 2 GB RAM
  zone         = var.zone

  tags = ["bastion"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu_2204.self_link
      size  = 20
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.lab_subnet.self_link
    # access_config assigns an external IP (NAT)
    access_config {}
  }

  metadata = {
    ssh-keys = var.ssh_public_key
  }

  labels = {
    role = "bastion"
    env  = "lab"
  }
}

# Prod server (no external IP, larger)
resource "google_compute_instance" "prod" {
  name         = "prod-server"
  machine_type = "e2-medium"             # 2 vCPU, 4 GB RAM
  zone         = var.zone

  tags = ["prod"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu_2204.self_link
      size  = 20
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.lab_subnet.self_link
    # NO access_config -> no external IP (private-only)
  }

  metadata = {
    ssh-keys = var.ssh_public_key
  }

  labels = {
    role = "prod"
    env  = "lab"
  }
}
