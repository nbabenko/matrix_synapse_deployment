# Matrix Synapse Deployment with Terraform and ThreeFold Grid

This project provides a deployment solution for Matrix Synapse using **Terraform** and the **ThreeFold Grid** for VM provisioning. The solution automates the setup of a Matrix Synapse server and includes automated backup and restore functionalities via AWS S3.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Project Structure](#project-structure)
- [Setup Instructions](#setup-instructions)
- [Backup & Restore](#backup--restore)
- [Variables](#variables)
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

Ensure to set the following values:
- `node_id`: ID of the node in the ThreeFold grid where the VM will be deployed.
- `vm_name`: Name for the Matrix Synapse VM.
- `cpu`: Number of CPU cores.
- `memory`: Amount of memory (in MB).
- `storage`: Disk storage (in MB).
- Paths to your SSL certificates and ThreeFold account memo.

### 3. Initialize and Apply Terraform
Initialize Terraform and apply the configuration to deploy the VM:

```bash
source terraform_config.sh
terraform init
terraform apply
```

Terraform will provision a new VM on the ThreeFold Grid. After the deployment is successful, it will output the VM’s IP address.

### 4. SSH into the VM and Configure Matrix Synapse
SSH into the VM using the provided IP address and run the setup script to configure Matrix Synapse:

```bash
ssh -i ~/.ssh/id_rsa root@<vm_ip_address>
cd /matrix-synapse
bash setup_matrix.sh
```

This will install Docker, configure Matrix Synapse, and set up SSL, NGINX, and email notifications.

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

## Variables

### Terraform Variables (Host Machine)
These variables are defined in `terraform_config.sh`:

- `TF_VAR_node_id`: ID of the ThreeFold Grid node where the VM will be deployed.
- `TF_VAR_vm_name`: Name for the VM.
- `TF_VAR_cpu`: Number of CPU cores for the VM.
- `TF_VAR_memory`: Amount of memory in MB.
- `TF_VAR_storage`: Disk storage in MB.
- `TF_VAR_ssh_private_key_to_use`: Path to the SSH private key.
- `TF_VAR_ssh_public_key_to_use`: Path to the SSH public key.
- `TF_VAR_ssl_certificate_key_path`: Path to the SSL certificate key.
- `TF_VAR_ssl_certificate_crt_path`: Path to the SSL certificate.
- `TF_VAR_ssl_certificate_ca_bundle_path`: Path to the CA bundle file.
- `TF_VAR_threefold_account_memo`: ThreeFold account mnemonic.

### Server-Side Variables
These variables are configured on the server itself via `server_config.sh`. You can edit them as needed to change the server's behavior:

- `SYNAPSE_SERVER_DOMAIN_NAME`: The domain name of the Matrix Synapse server.
- `AWS_ACCESS_KEY_ID`: AWS access key for S3 backup.
- `AWS_SECRET_ACCESS_KEY`: AWS secret access key for S3 backup.
- `AWS_BACKUP_ACCOUNT_S3_BUCKET_NAME`: Name of the S3 bucket where backups are stored.
- `ALERT_EMAIL`: Email address to send alerts in case of backup or disk space issues.
- `KEEP_HISTORY_FOREVER`: Set to `true` to keep message history and media files indefinitely. Set to `false` to enable retention policies.
- `LOG_FILE`: Path to the log file where backup errors will be recorded.
... etc

---

## Troubleshooting

### Common Issues
- **Docker Fails to Start**: If Docker fails to start, check the logs for errors:
    ```bash
    journalctl -u docker.service
    ```
- **Matrix Errors**: execute on the vm: docker logs synapse
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
