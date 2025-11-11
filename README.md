# Terraform on GCP: Bastion + Private Prod Lab (Runbook)

## Overview

This runbook documents, in step-by-step order, how to build and test a secure **GCP lab environment** using **Terraform**. The lab includes:

* A **Bastion Host** (public, 1 vCPU, 2GB RAM)
* A **Prod Server** (private-only, 2 vCPU, 4GB RAM)
* Network isolation (custom VPC, subnets, firewall rules)
* SSH access using a generated key pair
* Simulation of 30 concurrent users logging into the Prod server
* Cleanup and teardown (Terraform destroy + service account + bucket deletion)

This document starts from the point where the learner was **confused**, and the instructor reset the learning process with zero prior knowledge.

---

## 1. Prerequisites

### Local Setup

* **OS**: macOS (tested) or any Unix-like system
* **Terraform CLI** ≥ 1.5.0
* **Google Cloud SDK (`gcloud`)** ≥ 400.0

Verify installations:

```bash
terraform -version
gcloud version
```

### GCP Project Requirements

* A **GCP Project** with billing enabled
* User account with **Owner** or **Editor** permissions

Authenticate:

```bash
gcloud auth login
gcloud config set project <PROJECT_ID>
```

Enable required APIs:

```bash
gcloud services enable compute.googleapis.com
```

---

## 2. Terraform Folder Structure

```bash
mkdir -p ~/terraform-gcp-lab
cd ~/terraform-gcp-lab
```

```
terraform-gcp-lab/
├─ backend.tf
├─ versions.tf
├─ provider.tf
├─ variables.tf
├─ network.tf
├─ compute.tf
├─ terraform.tfvars
└─ outputs.tf (optional)
```

---

## 3. Service Account and Remote State Setup (GCS)

### 3.1 Create Service Account

```bash
PROJECT_ID="your-project-id"
SA_NAME="terraform-sa"

gcloud iam service-accounts create $SA_NAME \
  --display-name="Terraform service account for lab"
```

Grant required roles:

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/compute.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"
```

### 3.2 Generate Key File

```bash
gcloud iam service-accounts keys create ./terraform-sa-key.json \
  --iam-account="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
```

Add to `.gitignore`:

```bash
echo "terraform-sa-key.json" >> .gitignore
```

Set environment variable:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="$(pwd)/terraform-sa-key.json"
```

### 3.3 Create Remote State Bucket

```bash
BUCKET_NAME="tf-state-$(date +%s)"
REGION="asia-south1"
gsutil mb -p $PROJECT_ID -l $REGION -b on gs://$BUCKET_NAME/
gsutil versioning set on gs://$BUCKET_NAME
```

### 3.4 Configure Terraform Backend (`backend.tf`)

```hcl
terraform {
  backend "gcs" {
    bucket = "tf-state-yourbucketname"
    prefix = "terraform/state"
  }
}
```

Initialize Terraform:

```bash
terraform init
```

Expected output:

```
Successfully configured the backend "gcs"!
Terraform has been successfully initialized!
```

---

## 4. Provider and Variables Configuration

### 4.1 `versions.tf`

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}
```

### 4.2 `variables.tf`

```hcl
variable "project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "region" {
  type        = string
  default     = "asia-south1"
}

variable "zone" {
  type        = string
  default     = "asia-south1-a"
}

variable "lab_network_name" {
  type        = string
  default     = "lab-vpc"
}

variable "ssh_public_key" {
  description = "Public SSH key in the format 'username:ssh-ed25519 ...'"
  type        = string
}
```

### 4.3 `provider.tf`

```hcl
provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
```

### 4.4 `terraform.tfvars`

```hcl
project_id = "your-project-id"
ssh_public_key = "engineer:ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEWKf/GDmZoABOMf/2p9VeFXIjIMw5giCtTNv48DWPtV lab-bastion"
```

Validate:

```bash
terraform plan -var-file="terraform.tfvars"
```

---

## 5. Network and Firewall Setup

### `network.tf`

```hcl
resource "google_compute_network" "lab_vpc" {
  name                    = var.lab_network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "lab_subnet" {
  name          = "lab-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
  network       = google_compute_network.lab_vpc.id
}

resource "google_compute_firewall" "allow_ssh_bastion" {
  name    = "allow-ssh-bastion"
  network = google_compute_network.lab_vpc.self_link

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["bastion"]
}

resource "google_compute_firewall" "allow_internal_ssh" {
  name    = "allow-internal-ssh"
  network = google_compute_network.lab_vpc.self_link

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [google_compute_subnetwork.lab_subnet.ip_cidr_range]
  target_tags   = ["prod"]
}
```

Apply:

```bash
terraform apply -var-file="terraform.tfvars"
```

Expected: 4 resources created (VPC, Subnet, 2 firewalls).

---

## 6. Compute Instances

### Generate SSH Key Pair

```bash
ssh-keygen -t ed25519 -C "lab-bastion" -f ~/.ssh/lab_ed25519 -N ""
```

### `compute.tf`

```hcl
data "google_compute_image" "ubuntu_2204" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

resource "google_compute_instance" "bastion" {
  name         = "bastion"
  machine_type = "e2-custom-1-2048"
  zone         = var.zone
  tags         = ["bastion"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu_2204.self_link
      size  = 20
    }
  }

  network_interface {
    subnetwork   = google_compute_subnetwork.lab_subnet.self_link
    access_config {}
  }

  metadata = {
    ssh-keys = var.ssh_public_key
  }
}

resource "google_compute_instance" "prod" {
  name         = "prod-server"
  machine_type = "e2-medium"
  zone         = var.zone
  tags         = ["prod"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu_2204.self_link
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.lab_subnet.self_link
  }

  metadata = {
    ssh-keys = var.ssh_public_key
  }
}
```

Apply:

```bash
terraform apply -var-file="terraform.tfvars"
```

Expected output:

```
Apply complete! Resources: 2 added.
```

---

## 7. SSH Verification

### Fetch IPs

```bash
BASTION_IP=$(gcloud compute instances describe bastion --zone=asia-south1-a --format="get(networkInterfaces[0].accessConfigs[0].natIP)")
PROD_IP=$(gcloud compute instances describe prod-server --zone=asia-south1-a --format="get(networkInterfaces[0].networkIP)")
echo $BASTION_IP $PROD_IP
```

### SSH to Bastion

```bash
ssh -i ~/.ssh/lab_ed25519 engineer@$BASTION_IP
```

Expected: prompt `engineer@bastion:~$`

### SSH to Prod (via ProxyJump)

```bash
ssh -i ~/.ssh/lab_ed25519 -J engineer@$BASTION_IP engineer@$PROD_IP
```

Expected: prompt `engineer@prod-server:~$`

If you get `Permission denied (publickey)`, enable agent forwarding:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/lab_ed25519
ssh -A engineer@$BASTION_IP
ssh engineer@$PROD_IP
```

---

## 8. Simulate 30 Engineers Logging In

From **bastion**:

```bash
for i in $(seq 1 30); do
  ssh -o BatchMode=yes -o ConnectTimeout=5 engineer@$PROD_IP \
  "echo Engineer-$i connected from $(hostname) to $(hostname -I) at $(date)" &
done
wait
```

Sample Output:

```
Engineer-1 connected from bastion to 10.10.0.3 at Tue Nov 11 15:33:57 UTC 2025
Engineer-30 connected from bastion to 10.10.0.3 at Tue Nov 11 15:33:57 UTC 2025
```

---

## 9. Cleanup (Full Teardown)

### 9.1 Destroy Infra

```bash
terraform destroy -var-file="terraform.tfvars"
```

### 9.2 Remove GCS State

```bash
gsutil -m rm -r gs://<YOUR_BUCKET_NAME>/**
gsutil rb gs://<YOUR_BUCKET_NAME>
```

### 9.3 Delete Service Account and Keys

```bash
SA_EMAIL="terraform-sa@$PROJECT_ID.iam.gserviceaccount.com"
gcloud iam service-accounts keys list --iam-account="$SA_EMAIL"
gcloud iam service-accounts delete "$SA_EMAIL" --quiet
```

### 9.4 Clean Local Files

```bash
rm -f terraform-sa-key.json ~/.ssh/lab_ed25519 ~/.ssh/lab_ed25519.pub
```

### 9.5 Verify Cleanup

```bash
gcloud compute instances list
gcloud compute networks list
gsutil ls -p $PROJECT_ID
gcloud iam service-accounts list
```

All should return empty or unrelated results.

---

## 10. Summary

You successfully:

* Configured Terraform with GCS remote state
* Created a VPC, subnet, and firewall with correct tags
* Built Bastion + Prod Ubuntu VMs
* Secured access flow (public → private)
* Simulated multi-user SSH load
* Performed safe teardown and cleanup

You now have a working foundation for Terraform-based GCP automation and can easily expand to include IAM, modules, and multi-environment setups.

