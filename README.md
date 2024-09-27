
# Matrix Synapse Deployment with Terraform and ThreeFold Grid

This project provides a deployment solution for Matrix Synapse using **Terraform** and the **ThreeFold Grid** for VM provisioning. The solution automates the setup of a Matrix Synapse server and includes automated backup and restore functionalities via AWS S3.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Setup Instructions](#setup-instructions)
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

#### Server-Side Variables:
These variables are configured on the server via `server_config.sh` and can be modified to customize the server's behavior, including backup configurations, email alerts, and logging.

- **`SYNAPSE_SERVER_DOMAIN_NAME`**: The domain name of the Matrix Synapse server. This will be used for server identification, SSL configuration, and federation with other Matrix servers.
  
- **AWS S3 Backup Settings**:
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
