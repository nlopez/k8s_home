terraform {
  required_version = ">= 1.6"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }

  # State contains the cluster kubeconfig, so don't keep it on a laptop.
  # Uncomment and point at a DO Spaces bucket (S3-compatible) once it exists.
  # backend "s3" {
  #   endpoints                   = { s3 = "https://nyc3.digitaloceanspaces.com" }
  #   bucket                      = "CHANGEME-tfstate"
  #   key                         = "do-bootstrap/terraform.tfstate"
  #   region                      = "us-east-1" # required by the backend, ignored by Spaces
  #   skip_credentials_validation = true
  #   skip_requesting_account_id  = true
  #   skip_metadata_api_check     = true
  #   skip_region_validation      = true
  #   skip_s3_checksum            = true
  # }
}

provider "digitalocean" {
  # Reads DIGITALOCEAN_TOKEN from the environment.
}
