provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Application = var.application
      Customer    = var.customer
    }
  }
}

provider "aws" {
  alias  = "prod"
  region = var.region
  default_tags {
    tags = {
      Application = var.application
      Customer    = var.customer
    }
  }
}

terraform {

  backend "s3" {
    bucket                 = "operations-tfstate"
    key                    = "sftp-servers-terraform.tfstate"
    region                 = "us-east-1"
    skip_region_validation = true
  }
}
