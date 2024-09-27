Here's an updated version of your **README.md**, including instructions on setting up an AWS S3 account, creating access keys, and configuring permissions for backups:

---

# Matrix Synapse Deployment with Terraform and ThreeFold Grid

This project provides a deployment solution for Matrix Synapse using **Terraform** and the **ThreeFold Grid** for VM provisioning. The solution automates the setup of a Matrix Synapse server and includes automated backup and restore functionalities via AWS S3.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Setup Instructions](#setup-instructions)
- [Setting up AWS S3](#setting-up-aws-s3)
- [Synapse Configuration](#synapse-configuration)
- [User Registration](#user-registration)
- [Backup & Restore](#backup--restore)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## Prerequisites
Ensure the following software is installed and configured on your **local machine** (host):
- **Terraform** (>= v1.0.0): [Install Terraform](https://www.terraform.io/downloads.html)
- **SSH**: Access to the VM requires SSH key-based authentication.

No additional tools (e.g., Docker, AWS CLI) are required on the host machine.

## Project Structure
Here’s a breakdown of the main files and their purposes:

```
.
├── backup_matrix.sh                # Backup script for Matrix Synapse
├── config.sh                       # Configuration script for environment variables
├── main.tf                         # Terraform configuration for deploying the VM
├── restore_from_backup.sh          # Restore script for Matrix Synapse
├── setup_matrix.sh                 # Script to set up the Matrix Synapse server and configure Docker
├── terraform_config.sh.example     # Example configuration for Terraform variables
└── README.md                       # Project documentation (this file)
```

## Setup Instructions

### 1. Clone the Repository
```bash
git clone https://github.com/your-username/matrix-deployment.git
cd matrix-deployment
```

### 2. Configure Terraform Variables
Create a configuration file by copying `terraform_config.sh.example` to `terraform_config.sh` and update the values to match your environment:

```bash
cp terraform_config.sh.example terraform_config.sh
nano terraform_config.sh
```

#### Terraform Variables (Host Machine):
Set the following variables in `terraform_config.sh`:

- `TF_VAR_node_id`: ID of the ThreeFold Grid node where the VM will be deployed.
- `TF_VAR_vm_name`: Name for the Matrix Synapse VM.
- `TF_VAR_cpu`: Number of CPU cores for the VM.
- `TF_VAR_memory`: Amount of memory (in MB).
- `TF_VAR_storage`: Disk storage (in MB).
- `TF_VAR_ssh_private_key_to_use`: Path to the SSH private key.
- `TF_VAR_ssh_public_key_to_use`: Path to the SSH public key.
- `TF_VAR_ssl_certificate_key_path`: Path to the SSL certificate key.
- `TF_VAR_ssl_certificate_crt_path`: Path to the SSL certificate.
- `TF_VAR_ssl_certificate_ca_bundle_path`: Path to the CA bundle file.
- `TF_VAR_threefold_account_memo`: ThreeFold account mnemonic.

Here’s an improved version of the **Setting up AWS S3** section with better explanations, formatting, and examples:

---

## Setting up AWS S3

To use AWS S3 for backups, you will need to create an AWS account, set up an S3 bucket, generate access keys, and configure the necessary permissions.

### Step 1: Sign Up for an AWS Account
If you don’t have an AWS account, you can [sign up here](https://aws.amazon.com/free/). AWS offers a Free Tier that includes 5GB of S3 storage, which is sufficient for basic backup needs.

### Step 2: Create an S3 Bucket
1. Go to the [AWS S3 Console](https://s3.console.aws.amazon.com/s3/home).
2. Click **Create Bucket**.
3. Provide a unique name for your bucket (e.g., `matrix-synapse-backup`) and select a region close to your server.
4. Set the permissions to **private** to ensure your backups are secure and not publicly accessible.
5. Click **Create** to finish the process.

### Step 3: Generate AWS Access Keys
To interact with S3 programmatically from your server, you’ll need access keys.

1. Go to the **IAM Console** in AWS.
2. Create a new user specifically for your backups (e.g., `matrix-backup-user`). Ensure **Programmatic access** is selected (no console access needed).
3. Attach the following policy to the user, granting it access to the S3 bucket:
   ```json
   {
       "Version": "2012-10-17",
       "Statement": [
           {
               "Effect": "Allow",
               "Action": [
                   "s3:PutObject",
                   "s3:GetObject",
                   "s3:ListBucket",
                   "s3:DeleteObject"
               ],
               "Resource": [
                   "arn:aws:s3:::YOUR-BUCKET-NAME",
                   "arn:aws:s3:::YOUR-BUCKET-NAME/*"
               ]
           }
       ]
   }
   ```
   Replace `YOUR-BUCKET-NAME` with your S3 bucket name.

4. Download and securely store the **Access Key ID** and **Secret Access Key** for this user.

For more detailed steps, refer to [this AWS IAM guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_users_create.html).

### Step 4: Set Bucket Permissions
Next, configure the bucket permissions to allow access from your IAM user.

1. In the **S3 Console**, go to your newly created bucket.
2. Under **Permissions**, add the following bucket policy to grant your IAM user the appropriate access:
   ```json
   {
       "Version": "2012-10-17",
       "Statement": [
           {
               "Effect": "Allow",
               "Principal": {
                   "AWS": "arn:aws:iam::YOUR-AWS-ACCOUNT-ID:user/YOUR-BACKUP-USER"
               },
               "Action": [
                   "s3:PutObject",
                   "s3:GetObject",
                   "s3:ListBucket",
                   "s3:DeleteObject"
               ],
               "Resource": [
                   "arn:aws:s3:::YOUR-BUCKET-NAME",
                   "arn:aws:s3:::YOUR-BUCKET-NAME/*"
               ]
           }
       ]
   }
   ```
   Replace `YOUR-AWS-ACCOUNT-ID` with your AWS account ID and `YOUR-BUCKET-NAME` with the actual bucket name.

3. Apply and save the bucket policy.

### Step 5: Configure AWS Credentials on Your Server
After generating the access keys, configure them on your server in the `server_config.sh` file:

```bash
export AWS_ACCESS_KEY_ID="your-aws-access-key"
export AWS_SECRET_ACCESS_KEY="your-aws-secret-key"
export AWS_BACKUP_ACCOUNT_S3_BUCKET_NAME="your-bucket-name"
```

This will allow your Matrix Synapse server to interact with your S3 bucket for backups.

For more details on using AWS S3, refer to the [AWS S3 Getting Started Guide](https://aws.amazon.com/s3/getting-started/).

## Synapse Configuration

After running the `terraform apply` command, Matrix Synapse will be automatically configured with the following key components:

- **SSL Configuration**: NGINX is set up with SSL to ensure secure HTTPS communication. Ensure you have provided valid SSL certificate files during setup.
- **Federation Support**: The server is configured to federate with other Matrix servers, enabling communication across different Matrix instances.
- **Data Retention Policies**: Depending on your configuration (`KEEP_HISTORY_FOREVER`), the server will either retain all message history and media files indefinitely, or follow your chosen retention policies for cleaning up old data.

### Important Notes:
- **Domain Name and SSL**: Ensure that you have a valid domain name and SSL certificate ready for the initial setup. These are critical for securing communications and enabling federation.
- **DNS Configuration**: Once the deployment is complete and you have the server’s IP address, update your domain's DNS settings to point to the server’s public IP to ensure your domain correctly resolves to the Synapse server.

For further configuration options and more detailed setup instructions, please refer to the official [Matrix Synapse Documentation](https://matrix-org.github.io/synapse/latest/setup/installation.html).

### SSH into the VM and Configure Matrix Synapse further
SSH into the VM using the provided IP address and run the setup script to configure Matrix Synapse if you need any changes:
```bash
ssh root@<vm_ip_address>
```

---

## Backup & Restore

### Backup
Backups are handled automatically via a cron job. The `backup_matrix.sh` script runs nightly at 2:00 AM CET and uploads backups to the configured AWS S3 bucket.

To run the backup manually:
```bash
bash backup_matrix.sh
```

### Restore
To restore from the latest backup stored in S3, execute the following script:

```bash
bash restore_from_backup.sh
```

This script will stop the Matrix Synapse service, download the latest backup from S3, restore the data and SQLite database, and restart the Synapse server.

---

## Troubleshooting

### Common Issues
- **Docker Fails to Start**: If Docker fails to start, check the logs for errors:
    ```bash
    journalctl -u docker.service
    ```
- **Matrix Errors**: To view logs from the Matrix Synapse container:
    ```bash
    docker logs synapse
    ```
- **Backup Errors**: Backup logs are stored in `/tmp/matrix_synapse_backup_error.log`. Check the log for details on any backup failures.

### Disk Space Alerts
The backup script monitors disk space and sends an alert if less than 5% is free. Ensure that you have enough disk space before running large operations.

---

## Contributing
Contributions are welcome! Feel free to submit a pull request or open an issue for any bugs, improvements, or features.

### Guidelines:
- Ensure all tests pass.
- Write clear commit messages.
- Follow the project structure and coding conventions.

---

## License
This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
