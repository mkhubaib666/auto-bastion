import os
import json
import hmac
import hashlib
import time
import logging
import boto3
import yaml
import subprocess
import tempfile
from urllib.parse import parse_qs
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize clients (will be configured in handler)
s3 = boto3.client("s3")
dynamodb = boto3.resource("dynamodb")
events = boto3.client("events")
config = {}


def get_config():
    """Loads configuration from S3."""
    global config
    if not config:
        bucket = os.environ["CONFIG_BUCKET"]
        key = os.environ["CONFIG_KEY"]
        response = s3.get_object(Bucket=bucket, Key=key)
        config = yaml.safe_load(response["Body"])
    return config


def verify_slack_request(headers, body):
    """Verifies the request signature from Slack."""
    slack_signing_secret = get_config()["slack"]["signing_secret"]
    timestamp = headers["x-slack-request-timestamp"]
    signature = headers["x-slack-signature"]

    if abs(time.time() - int(timestamp)) > 60 * 5:
        return False

    sig_basestring = f"v0:{timestamp}:{body}".encode("utf-8")
    my_signature = (
        "v0="
        + hmac.new(
            slack_signing_secret.encode("utf-8"), sig_basestring, hashlib.sha256
        ).hexdigest()
    )
    return hmac.compare_digest(my_signature, signature)


def parse_command(body):
    """Parses the /request-access command text."""
    parsed_body = parse_qs(body)
    text = parsed_body.get("text", [""])[0]
    parts = text.split()
    params = {}
    for part in parts:
        if ":" in part:
            key, value = part.split(":", 1)
            params[key] = value
    return {
        "target": params.get("target"),
        "duration": int(params.get("duration", 60)),
        "user_id": parsed_body.get("user_id", [""])[0],
        "user_name": parsed_body.get("user_name", [""])[0],
        "response_url": parsed_body.get("response_url", [""])[0],
    }


def run_terraform(command, working_dir):
    """Executes a Terraform command."""
    logger.info(f"Running 'terraform {command}' in {working_dir}")
    subprocess.run(["cp", "/opt/terraform", "/tmp/terraform"], check=True)
    subprocess.run(["chmod", "+x", "/tmp/terraform"], check=True)

    process = subprocess.run(
        [f"/tmp/terraform {command}"],
        capture_output=True,
        shell=True,
        cwd=working_dir,
        text=True,
    )
    if process.returncode != 0:
        logger.error(f"Terraform Error: {process.stderr}")
        raise Exception(f"Terraform command failed: {process.stderr}")
    logger.info(f"Terraform Output: {process.stdout}")
    return process.stdout


def handler(event, context):
    """Main Lambda handler."""
    try:
        app_config = get_config()
        slack_client = WebClient(token=app_config["slack"]["bot_token"])
    except Exception as e:
        logger.error(f"Configuration error: {e}")
        return {"statusCode": 500, "body": "Internal configuration error."}

    body = event["body"]
    if not verify_slack_request(event["headers"], body):
        return {"statusCode": 403, "body": "Verification failed."}

    command = parse_command(body)
    try:
        slack_client.chat_postMessage(
            channel=command["user_id"],
            text=(
                f"Got it, {command['user_name']}! Provisioning access to"
                f" `{command['target']}`. This might take a minute..."
            ),
        )
    except SlackApiError as e:
        logger.error(f"Error posting initial message: {e}")

    try:
        target_config = app_config["targets"].get(command["target"])
        if not target_config:
            raise ValueError(f"Target '{command['target']}' not found in config.")

        request_id = f"{command['user_name']}-{int(time.time())}"

        with tempfile.TemporaryDirectory() as tmpdir:
            subprocess.run(
                f"cp -r {os.environ['LAMBDA_TASK_ROOT']}/terraform_module/* {tmpdir}/",
                shell=True,
                check=True,
            )

            tfvars = {
                "user_ssh_key_name": request_id,
                "user_public_ip": event["requestContext"]["http"]["sourceIp"],
                "target_sg_id": target_config["target_sg_id"],
                "target_port": target_config["target_port"],
                "aws_region": os.environ["AWS_REGION"],
                "tags": {
                    "ManagedBy": "Auto-Bastion",
                    "User": command["user_name"],
                    "RequestId": request_id,
                },
            }
            with open(os.path.join(tmpdir, "terraform.tfvars.json"), "w") as f:
                json.dump(tfvars, f)

            run_terraform("init -input=false", tmpdir)
            run_terraform("apply -auto-approve -json", tmpdir)

            output_json = run_terraform("output -json", tmpdir)
            outputs = json.loads(output_json)
            bastion_ip = outputs["bastion_public_ip"]["value"]
            private_key = outputs["ssh_private_key_pem"]["value"]

        events.put_rule(
            Name=request_id,
            ScheduleExpression=f"rate({command['duration']} minutes)",
            State="ENABLED",
            Description=f"Auto-Bastion teardown for {request_id}",
        )
        events.put_targets(
            Rule=request_id,
            Targets=[
                {
                    "Id": "destroyer-lambda",
                    "Arn": os.environ["DESTROYER_LAMBDA_ARN"],
                    "Input": json.dumps({"request_id": request_id, "tfvars": tfvars}),
                }
            ],
        )

        ssh_command = (
            f"ssh -i {request_id}.pem -L "
            f"{target_config['target_port']}:{target_config['target_host']}:{target_config['target_port']} "
            f"ec2-user@{bastion_ip}"
        )
        slack_client.files_upload_v2(
            channel=command["user_id"],
            title=f"{request_id}.pem",
            filename=f"{request_id}.pem",
            content=private_key,
            initial_comment=(
                f"Access granted for *{command['duration']} minutes*!\n\n"
                f"1. Save the attached file as `{request_id}.pem` and run `chmod 400 {request_id}.pem`.\n"
                "2. Use this command to connect:\n"
                f"```{ssh_command}```"
            ),
        )

    except Exception as e:
        logger.error(f"Failed to provision: {e}")
        slack_client.chat_postMessage(
            channel=command["user_id"],
            text=f"Sorry, something went wrong while provisioning access: `{e}`",
        )
        return {"statusCode": 500, "body": "Error during provisioning."}

    return {"statusCode": 200, "body": ""}