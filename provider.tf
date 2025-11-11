# provider config (project, region, credentials)

provider "google" {
  project = var.project_id
  region  = "var.region"
  zone = var.zone
  }