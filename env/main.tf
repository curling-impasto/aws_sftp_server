module "aggregator_sftp" {
  source = "../modules/sftp_servers"

  sftp_server_name = "dev-server"
  vpc_id           = "vpc-01234"
  subnet_id        = "subnet-01234"
  sftp_users = [
    { username = "dev" }
  ]
  public_subnet_cidr_blocks = [
    "8.8.8.8/32"
  ]
  custom_hostname  = "aggregator-server.abc.com"
  lambda_role_arns = ["arn:aws:iam::123456789:role/general-role"]
}
