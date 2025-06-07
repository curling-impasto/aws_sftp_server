output "sftp_server_id" {
  value       = aws_transfer_server.transfer.id
  description = "ID of the created SFTP server"
}