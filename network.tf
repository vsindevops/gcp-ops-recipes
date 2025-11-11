# VPC, subnets, firewall rules
resource "google_compute_network" "lab_vpc" {
  name                    = var.lab_network_name
  auto_create_subnetworks = false
  description             = "VPC for Terraform lab (bastion + prod)"
}

resource "google_compute_subnetwork" "lab_subnet" {
  name          = "lab-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
  network       = google_compute_network.lab_vpc.id
  description   = "Private subnet for lab instances"
}

# Allow SSH from the internet to instances tagged "bastion"
resource "google_compute_firewall" "allow_ssh_bastion" {
  name    = "allow-ssh-bastion"
  network = google_compute_network.lab_vpc.self_link
  description = "Allow TCP/22 from anywhere to bastion instances"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # 0.0.0.0/0 per your choice
  source_ranges = ["0.0.0.0/0"]

  # Only apply to instances with tag "bastion"
  target_tags = ["bastion"]
}

# Allow SSH from the lab subnet to instances tagged "prod"
resource "google_compute_firewall" "allow_internal_ssh" {
  name    = "allow-internal-ssh"
  network = google_compute_network.lab_vpc.self_link
  description = "Allow TCP/22 from lab subnet to prod instances"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [google_compute_subnetwork.lab_subnet.ip_cidr_range]

  target_tags = ["prod"]
}
