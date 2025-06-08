terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# S3 bucket to store Terraform state for the ephemeral bastions
resource "aws_s3_bucket" "terraform_state" {
  bucket = "${var.project_name}-tfstate-${random_id.bucket_suffix.hex}"
  # Enable versioning and encryption for production
}

# S3 bucket to store the config.yaml file
resource "aws_s3_bucket" "config_bucket" {
  bucket = "${var.project_name}-config-${random_id.bucket_suffix.hex}"
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}

# DynamoDB table for state locking and auditing
resource "aws_dynamodb_table" "state_lock" {
  name         = "${var.project_name}-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "request_id"

  attribute {
    name = "request_id"
    type = "S"
  }
}

# --- Lambda Function Packaging ---

# Download the Terraform binary for use in the Lambda layer
resource "null_resource" "download_terraform" {
  provisioner "local-exec" {
    command = "curl -o terraform.zip https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_linux_arm64.zip && unzip terraform.zip && rm terraform.zip"
  }
  triggers = {
    always_run = timestamp()
  }
}

# Create a Lambda Layer containing the Terraform binary
resource "aws_lambda_layer_version" "terraform_layer" {
  layer_name          = "${var.project_name}-terraform-layer"
  filename            = "terraform" # This should point to the downloaded binary
  compatible_runtimes = ["python3.9"]
  depends_on          = [null_resource.download_terraform]
}

# Package the provisioner Lambda function
data "archive_file" "provisioner_zip" {
  type        = "zip"
  source_dir  = "../../src/provisioner/"
  output_path = "provisioner.zip"
}

# Package the destroyer Lambda function
data "archive_file" "destroyer_zip" {
  type        = "zip"
  source_dir  = "../../src/destroyer/"
  output_path = "destroyer.zip"
}

# --- Lambda Function Resources ---

resource "aws_lambda_function" "provisioner" {
  function_name    = "${var.project_name}-provisioner"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "main.handler"
  runtime          = "python3.9"
  timeout          = 300 # 5 minutes
  memory_size      = 256
  filename         = data.archive_file.provisioner_zip.output_path
  source_code_hash = data.archive_file.provisioner_zip.output_base64sha256

  layers = [aws_lambda_layer_version.terraform_layer.arn]

  environment {
    variables = {
      CONFIG_BUCKET        = aws_s3_bucket.config_bucket.id
      CONFIG_KEY           = "config.yaml"
      TF_STATE_BUCKET      = aws_s3_bucket.terraform_state.id
      DESTROYER_LAMBDA_ARN = aws_lambda_function.destroyer.arn
    }
  }
}

resource "aws_lambda_function" "destroyer" {
  function_name    = "${var.project_name}-destroyer"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "main.handler"
  runtime          = "python3.9"
  timeout          = 300
  memory_size      = 256
  filename         = data.archive_file.destroyer_zip.output_path
  source_code_hash = data.archive_file.destroyer_zip.output_base64sha256

  layers = [aws_lambda_layer_version.terraform_layer.arn]
}

# --- API Gateway for Slack ---

resource "aws_apigatewayv2_api" "slack_api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  api_id           = aws_apigatewayv2_api.slack_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.provisioner.invoke_arn
}

resource "aws_apigatewayv2_route" "slack_route" {
  api_id    = aws_apigatewayv2_api.slack_api.id
  route_key = "POST /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration.id}"
}

resource "aws_lambda_permission" "api_gateway_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.provisioner.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.slack_api.execution_arn}/*/*"
}