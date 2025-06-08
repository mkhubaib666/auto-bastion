variable "aws_region" {
  description = "The AWS region to deploy the Auto-Bastion system in."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "A name for the project, used to prefix resources."
  type        = string
  default     = "auto-bastion"
}