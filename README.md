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
- [Verification and Testing](#verification-and-testing) 
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
├── server_config.sh.example        # Example configuration for the Synapse Server
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
Create a configuration file by copying `terraform_config.sh.example` to `terraform_config.sh` and `server_config.sh.example` to `server_config.sh` and update the values to match your environment:

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
- `TF_VAR_ssl_certificate_ca_bundle_path`: Path to the SSL CA bundle file.
- `TF_VAR_threefold_account_memo`: ThreeFold account mnemonic.

#### Server-Side Variables:
These variables are configured on the server via `server_config.sh` and can be modified to customize the server's behavior, including backup configurations, email alerts, and logging.
- **`SYNAPSE_SERVER_DOMAIN_NAME`**: The domain name of the Matrix Synapse server. This will be used for server identification, SSL configuration, and federation with other Matrix servers.
  
- **AWS S3 Backup Settings**: For set up instructions see [Setting up AWS S3](#setting-up-aws-s3)
  - **`AWS_ACCESS_KEY_ID`**: Your AWS access key for authentication when interacting with S3 for backups. 
  - **`AWS_SECRET_ACCESS_KEY`**: Your AWS secret access key for secure access to S3. 
  - **`AWS_BACKUP_ACCOUNT_S3_BUCKET_NAME`**: The name of the S3 bucket where Synapse backups will be stored. 
- **Data Retention Settings**:
  - **`KEEP_HISTORY_FOREVER`**: Set this to `true` if you want to retain all message history and media files indefinitely. Set it to `false` to enable the server’s retention policies, which will periodically clean up old messages and media.
- **Email Alert Settings**:
  - **`ALERT_EMAIL`**: The recipient email address for backup failure or disk space alerts.
  - **`EMAIL_FROM`**: The sender email address that will be used for sending these alert emails.
  - **`EMAIL_PASSWORD`**: The password for the `EMAIL_FROM` account. If you’re using Gmail, you must use an [App Password](https://support.google.com/accounts/answer/185833?hl=en).
  - **`MAILHUB`**: The SMTP server address for sending email notifications (e.g., `smtp.gmail.com:587` for Gmail).

- **Logging Settings**:
  - **`LOG_FILE`**: The path to the log file where backup errors and other operational logs will be recorded. This file will help diagnose issues with backups or the system.

### 3. Initialize and Apply Terraform
Initialize Terraform and apply the configuration to deploy the VM:

```bash
source terraform_config.sh
terraform init
terraform apply
```

Terraform will provision a new VM on the ThreeFold Grid. After the deployment is successful, it will output the VM’s IP address.

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
After generating the access keys, configure them on your server in the `server_config.sh` file. See :

```bash
export AWS_ACCESS_KEY_ID="your-aws-access-key"
export AWS_SECRET_ACCESS_KEY="your-aws-secret-key"
export AWS_BACKUP_ACCOUNT_S3_BUCKET_NAME="your-bucket-name"
```

This will allow your Matrix Synapse server to interact with your S3 bucket for backups.

For more details on using AWS S3, refer to the [AWS S3 Getting Started Guide](https://aws.amazon.com/s3/getting-started/).

##

 Synapse Configuration

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

## User Registration
By default, this Matrix Synapse server does **not** allow open registration to new users via the web interface for security reasons. If you want to register new users, you must do so via the command line.
### Register a New User via Command Line
To register a new user, SSH into the VM and run the following command:
```bash
docker exec -it synapse register_new_matrix_user http://localhost:8008 -c /data/homeserver.yaml
```
You will be prompted to provide:
1. **Username**: The desired username for the new user.
2. **Password**: The password for the new user.
3. **Admin Rights**: Whether or not the user should have admin rights on the server.
For more detailed instructions on user registration, refer to the official documentation: [Registering Users in Synapse](https://matrix-org.github.io/synapse/latest/usage/administration/admin_api/user_admin_api.html).

---

## Backup & Restore

### Backup
Backups are handled automatically via a cron job. The `backup_matrix.sh` script runs nightly at 1:00 AM UTC and uploads backups to the configured AWS S3 bucket.

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

## Verification and Testing

### Verify Synapse Version Using `curl`

To check if the Synapse server is running and determine its version, use the following `curl` command from your command line:

```bash
curl -X GET http://localhost:8008/_matrix/client/versions
```

A successful response should return a JSON object with the supported versions of the Matrix protocol.

Example response:
```json
{
  "versions": ["r0.0.1", "r0.1.0", "r0.2.0"],
  "unstable_features": {
    "m.lazy_load_members": true,
    "m.require_identity_server": false
  }
}
```

### Verify Server Federation Status

Use the [Matrix Federation Tester](https://federationtester.matrix.org/) to check if your Synapse server can federate with other Matrix servers.

1. Visit the Federation Tester website.
2. Enter your server's domain (e.g., `matrix.example.com`).
3. Click **Go!** to run the test.

The tool will show if your server is publicly accessible and whether it can federate properly with other servers.

### Login via a Matrix Client

Test logging into the Matrix Synapse server using any Matrix client like:

- **Element**
- **FluffyChat**
- **Quaternion**

1. Open the Matrix client.
2. Enter the server’s custom homeserver URL (e.g., `https://matrix.example.com`).
3. Use the credentials for a user created via the command line.
4. Ensure that you can log in, send, and receive messages.

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
- Ensure the changes are tested and works.
- Write clear commit messages.
- Follow the project structure and coding conventions.

---

## License
This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
