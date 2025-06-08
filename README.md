# Auto-Bastion


**Ephemeral, Just-in-Time bastion hosts for your private AWS resources, managed entirely from Slack.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![CI](https://github.com/mkhubaib666/auto-bastion/actions/workflows/ci.yml/badge.svg)](https://github.com/mkhubaib666/auto-bastion/actions/workflows/ci.yml)

Auto-Bastion solves the problem of secure, temporary access to private resources (like databases, caches, or servers) in your VPC. It eliminates the need for costly, high-risk permanent bastion hosts or complex VPNs.

---

### **The Problem**

Developers often need temporary SSH access for debugging or database inspection. The common solutions are flawed:

-   **Permanent Bastion Host:** Always on, costing money and presenting a constant security risk that needs patching and monitoring.
-   **Manual IAM/SSH Management:** Slow, error-prone, and hard to audit. Access is often forgotten and left open.
-   **Complex Access Tools:** Overkill for simple, temporary needs and require significant setup and maintenance.

### **The Solution: Auto-Bastion**

Auto-Bastion provides access on-demand via a simple Slack command.

1.  **Request:** A developer requests access from Slack: `/request-access target:rds-main-replica duration:30m`
2.  **Provision:** Auto-Bastion securely provisions a tiny, temporary bastion host using Terraform. It creates a unique SSH key and firewall rules locked down to the user's IP.
3.  **Connect:** The developer receives a DM in Slack with the SSH command and the private key.
4.  **Destroy:** After the requested duration, the bastion and all its resources are automatically destroyed.

**The result: No lingering costs. No permanent attack surface. A full audit trail in Slack and AWS.**


### **Features**

-   **Just-in-Time (JIT) Access:** Bastions exist only when you need them.
-   **ChatOps Driven:** Lives where your developers are—Slack.
-   **Secure by Default:**
    -   Unique, temporary SSH key for every session.
    -   Firewall rules are dynamically created for the requesting user's IP.
    -   Short-lived, auto-revoked access.
-   **Cost-Effective:** Only pay for a `t4g.nano` instance for the minutes you use it.
-   **IaC Native:** Built on Terraform, the industry standard for Infrastructure as Code.

### **Getting Started**

1.  **Prerequisites:**
    -   An AWS Account
    -   A Slack Workspace & Admin Permissions
    -   Terraform >= 1.5 installed
    -   AWS CLI configured

2.  **Deploy the Auto-Bastion System:**
    -   Clone this repository.
    -   Navigate to the `/terraform/live` directory.
    -   Run `terraform init` and `terraform apply`. This will deploy the core Lambdas, IAM Roles, and DynamoDB table. Note the outputs.

3.  **Configure Slack:**
    -   Create a new Slack App.
    -   Create a Slash Command (`/request-access`) and point the Request URL to the API Gateway endpoint from the Terraform output.
    -   Install the app to your workspace and get the Bot User OAuth Token.

4.  **Configure the System:**
    -   Update the `config.example.yaml` with your details (Slack tokens, target resources).
    -   Rename it to `config.yaml` and upload it to the S3 configuration bucket created by Terraform.

### **Usage**

In your designated Slack channel, type:

`/request-access target:<your-target-name> duration:<minutes>`

**Example:**

`/request-access target:rds-main-replica duration:60`

You will receive a DM with your connection details.

---

