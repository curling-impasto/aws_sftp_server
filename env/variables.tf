variable "region" {
  type        = string
  description = "Region of the S3 bucket"
  default     = "us-east-1"
}

variable "application" {
  type        = string
  description = "Application that uses the S3 bucket"
  default     = "ctx"
}

variable "customer" {
  type        = string
  description = "Application that uses the S3 bucket"
  default     = "mvnoc"
}
