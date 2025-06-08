variable "user_ssh_key_name" {
  description = "The name of the temporary SSH key pair to create."
  type        = string
}

variable "user_public_ip" {
  description = "The public IP of the user requesting access. Used for the SG."
  type        = string
}

variable "target_sg_id" {
  description = "The security group ID of the target resource (e.g., RDS)."
  type        = string
}

variable "target_port" {
  description = "The port to allow access to on the target resource."
  type        = number
}

variable "instance_type" {
  description = "The EC2 instance type for the bastion."
  type        = string
  default     = "t4g.nano"
}

variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
}

variable "tags" {
  description = "A map of tags to assign to all resources."
  type        = map(string)
  default     = {}
}