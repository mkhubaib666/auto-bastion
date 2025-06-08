# This module creates a temporary SSH key, a bastion host, and the
# necessary security groups for a JIT access session.

# Find the latest Amazon Linux 2 AMI for ARM64 architecture
data "aws_ami" "amazon_linux_2_arm" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-arm64-gp2"]
  }
}

# Create a new, unique SSH key pair for this session
resource "tls_private_key" "user_ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.user_ssh_key_name
  public_key = tls_private_key.user_ssh_key.public_key_openssh
}

# Security group for the bastion host itself
resource "aws_security_group" "bastion_sg" {
  name        = "auto-bastion-sg-${var.user_ssh_key_name}"
  description = "Allow SSH from user and egress to target. Managed by Auto-Bastion."

  # Allow SSH ingress only from the requesting user's IP
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.user_public_ip}/32"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "auto-bastion-sg-${var.user_ssh_key_name}"
  })
}

# Allow traffic from the bastion to the target resource (e.g., RDS)
resource "aws_security_group_rule" "bastion_to_target" {
  type                     = "ingress"
  from_port                = var.target_port
  to_port                  = var.target_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion_sg.id
  security_group_id        = var.target_sg_id
  description              = "Allow access from Auto-Bastion host"
}

# The ephemeral bastion host
resource "aws_instance" "bastion_host" {
  ami           = data.aws_ami.amazon_linux_2_arm.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.generated_key.key_name
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  tags = merge(var.tags, {
    Name      = "auto-bastion-host-${var.user_ssh_key_name}"
    ManagedBy = "Auto-Bastion"
  })
}