import os
import json
import logging
import boto3
import subprocess
import tempfile

logger = logging.getLogger()
logger.setLevel(logging.INFO)

events = boto3.client("events")


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
    """Lambda handler to destroy resources."""
    request_id = event["request_id"]
    tfvars = event["tfvars"]
    logger.info(f"Starting teardown for request: {request_id}")

    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            subprocess.run(
                f"cp -r {os.environ['LAMBDA_TASK_ROOT']}/terraform_module/* {tmpdir}/",
                shell=True,
                check=True,
            )
            with open(os.path.join(tmpdir, "terraform.tfvars.json"), "w") as f:
                json.dump(tfvars, f)

            run_terraform("init -input=false", tmpdir)
            run_terraform("destroy -auto-approve", tmpdir)

        events.remove_targets(Rule=request_id, Ids=["destroyer-lambda"])
        events.delete_rule(Name=request_id)

        logger.info(f"Successfully destroyed resources for {request_id}")

    except Exception as e:
        logger.error(f"Failed to destroy resources for {request_id}: {e}")
        raise

    return {"statusCode": 200, "body": json.dumps("Teardown complete.")}
