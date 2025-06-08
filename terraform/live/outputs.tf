output "api_gateway_endpoint" {
  description = "The endpoint URL for your Slack command. Include the trailing slash."
  value       = "${aws_apigatewayv2_api.slack_api.api_endpoint}/"
}

output "config_bucket_name" {
  description = "The name of the S3 bucket where you should upload your config.yaml."
  value       = aws_s3_bucket.config_bucket.id
}

output "terraform_state_bucket_name" {
  description = "The name of the S3 bucket that will store bastion state files."
  value       = aws_s3_bucket.terraform_state.id
}