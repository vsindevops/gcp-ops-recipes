terraform {
  backend "gcs" {
    bucket = "week1-tf-state-1762867848"
    prefix = "terraform/state"
    
  }
}