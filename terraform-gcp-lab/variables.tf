# variables (project_id, region, machine sizes, ssh key)
variable "project_id" {
  description = "GCP project id to create resources in"
  type        = string
  default     = "infraslash"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "asia-south1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "asia-south1-a"
}

variable "lab_network_name" {
  description = "Name of the VPC network for the lab"
  type        = string
  default     = "lab-vpc"
}

variable "ssh_public_key" {
  description = "Public SSH key in the format 'username:ssh-rsa ...' or 'username:ssh-ed25519 ...'"
  type        = string
}
