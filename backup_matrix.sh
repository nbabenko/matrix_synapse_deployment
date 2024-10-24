#!/bin/bash

set -e

# Load variables from the config file
source /matrix-synapse/server_config.sh

EMAIL_SUBJECT="Matrix Synapse Backup Failed"
EMAIL_BODY="The Matrix Synapse backup script encountered an error and failed to complete. Please see the log output below for details:"

# Function to send an email alert with the error log
send_alert() {
  LOG_CONTENT=$(tail -n 50 $LOG_FILE)  # Include the last 50 lines of the log
  echo "Sending alert email to $ALERT_EMAIL..."
  echo -e "To: $ALERT_EMAIL\nFrom: no-reply@$SYNAPSE_SERVER_DOMAIN_NAME\nSubject: $EMAIL_SUBJECT\n\n$EMAIL_BODY\n\n$LOG_CONTENT" | /usr/sbin/ssmtp $ALERT_EMAIL
}

# Trap errors, log the error, and send an alert if the script fails
trap 'echo "Backup script failed." | tee -a $LOG_FILE; send_alert' ERR

# Function to check disk space and send an email alert if below 5%
check_disk_space() {
    # Define the threshold for free disk space (in percentage)
    THRESHOLD=5

    # Get the current disk usage for the root (/) partition
    DISK_USAGE=$(df / | grep / | awk '{print $5}' | sed 's/%//')

    # If disk usage is greater than or equal to (100 - THRESHOLD), send an alert
    if [ "$DISK_USAGE" -ge $((100 - THRESHOLD)) ]; then
        echo "Disk space is below threshold. Sending alert email..."
        DISK_ALERT_SUBJECT="Matrix Synapse Server Disk Space Alert: Less than 5% Free"
        DISK_ALERT_BODY="Warning: The Matrix Synapse server is running low on disk space. Less than 5% is available.\n\nCurrent disk usage: ${DISK_USAGE}%."

        # Send the email using ssmtp
        echo -e "To: $ALERT_EMAIL\nFrom: no-reply@$SYNAPSE_SERVER_DOMAIN_NAME\nSubject: $DISK_ALERT_SUBJECT\n\n$DISK_ALERT_BODY" | /usr/sbin/ssmtp $ALERT_EMAIL

        if [ $? -eq 0 ]; then
            echo "Disk space alert email sent successfully."
        else
            echo "Failed to send disk space alert email." >&2
        fi
    else
        echo "Disk space is sufficient: $DISK_USAGE% used."
    fi
}

# Check disk space before proceeding with the backup
check_disk_space

# Variables for backup
BACKUP_DIR="/matrix-synapse/data"
RESTIC_REPOSITORY="s3:s3.amazonaws.com/${AWS_BACKUP_ACCOUNT_S3_BUCKET_NAME}"
export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"

# Test AWS CLI access to the S3 bucket
echo "Verifying S3 bucket access with AWS CLI..."
aws s3 ls "s3://${AWS_BACKUP_ACCOUNT_S3_BUCKET_NAME}" --region $AWS_BUCKET_REGION
if [ $? -ne 0 ]; then
    echo "Error: Unable to access S3 bucket. Please check IAM permissions."
    exit 1
fi

export RESTIC_PASSWORD="$BACKUP_ENCRYPTION_PASSWORD"

# Check if the Restic repository is already initialized
echo "Checking if Restic repository is initialized..."
if ! restic -r "$RESTIC_REPOSITORY" snapshots > /dev/null 2>&1; then
    echo "Restic repository not found. Initializing..."
    restic -r "$RESTIC_REPOSITORY" init
    if [ $? -ne 0 ]; then
        echo "Error: Failed to initialize Restic repository."
        exit 1
    fi
    echo "Restic repository initialized successfully."
else
    echo "Restic repository already initialized."
fi

# Back up SQLite database using sqlite3 .backup command inside the container
echo "Backing up SQLite database..."
docker exec synapse sqlite3 /data/homeserver.db ".backup '/data/homeserver.db.backup'"

# Copy the SQLite backup from the container to the host
echo "Copying the SQLite backup to the host..."
docker cp synapse:/data/homeserver.db.backup "$BACKUP_DIR/homeserver.db.backup"

# Perform the backup using Restic, including the database backup
echo "Starting backup with Restic..."
restic -r "$RESTIC_REPOSITORY" backup "$BACKUP_DIR" --tag "synapse-backup" --verbose --exclude "$BACKUP_DIR/homeserver.db" --exclude "$BACKUP_DIR/homeserver.db-wal" --exclude "$BACKUP_DIR/homeserver.db-shm" 

# Apply retention policy to keep only the last 3 daily snapshots
echo "Applying retention policy to keep only the last 3 daily snapshots..."
restic -r "$RESTIC_REPOSITORY" forget --keep-daily 3 --prune
echo "Retention policy applied successfully."

echo "Backup completed successfully."
