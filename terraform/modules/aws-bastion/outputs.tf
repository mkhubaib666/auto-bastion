output "bastion_public_ip" {
  description = "The public IP address of the created bastion host."
  value       = aws_instance.bastion_host.public_ip
}

output "ssh_private_key_pem" {
  description = "The private key for the user to connect to the bastion. Handle with care."
  value       = tls_private_key.user_ssh_key.private_key_pem
  sensitive   = true
}