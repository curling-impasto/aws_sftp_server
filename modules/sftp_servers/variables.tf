variable "sftp_server_name" {
  type        = string
  description = "Name of Source CW log group"
  default     = "sftp-server"
}

variable "vpc_id" {
  type        = string
  description = "ID of VPC where endpoint will be created"
}

variable "subnet_id" {
  type        = string
  description = "ID of Subent where endpoint will be created"
}

variable "public_subnet_cidr_blocks" {
  description = "List of public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24"]
}

variable "custom_hostname" {
  type        = string
  description = "Custom DNS name of SFTP server"
}

variable "sftp_users" {
  type = list(object({
    username = string
  }))
  description = "SFTP users that will use the Server"
}

variable "lambda_role_arns" {
  type        = list(string)
  description = "List of ARN(s) of IAM role(s) attached to the lambda"
}
