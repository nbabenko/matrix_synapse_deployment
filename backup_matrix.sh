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
  echo -e "To: $ALERT_EMAIL\nFrom: no-reply@$SYNAPSE_SERVER_DOMAIN_NAME\nSubject: $EMAIL_SUBJECT\n\n$EMAIL_BODY\n\n$LOG_CONTENT" | ssmtp $ALERT_EMAIL
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
        echo -e "To: $ALERT_EMAIL\nFrom: no-reply@$SYNAPSE_SERVER_DOMAIN_NAME\nSubject: $DISK_ALERT_SUBJECT\n\n$DISK_ALERT_BODY" | ssmtp $ALERT_EMAIL

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
TIMESTAMP=$(date +%Y%m%d%H%M%S)
BACKUP_DIR="/tmp/matrix-synapse-backup-$TIMESTAMP"
DATA_DIR="/matrix-synapse/data"
ARCHIVE_NAME="matrix-synapse-backup-$TIMESTAMP.tar.gz"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Copy data directory
echo "Backing up data directory..."
rsync -a --delete \
  --exclude 'homeserver.db' \
  --exclude 'homeserver.db-wal' \
  --exclude 'homeserver.db-shm' \
  "$DATA_DIR/" "$BACKUP_DIR/data/"


# Back up SQLite database using sqlite3 .backup command inside the container
echo "Backing up SQLite database..."
docker exec synapse sqlite3 /data/homeserver.db ".backup '/data/homeserver.db.backup'"

# Copy the SQLite backup from the container to the host
echo "Copying the SQLite backup to the host..."
docker cp synapse:/data/homeserver.db.backup "$BACKUP_DIR/homeserver.db"

# Create a compressed archive of the backup
echo "Creating compressed archive..."
tar -czf "/tmp/$ARCHIVE_NAME" -C "/tmp" "matrix-synapse-backup-$TIMESTAMP"

# Remove all but the latest backup from the S3 bucket
echo "Cleaning old backups from S3..."
LATEST_BACKUP=$(aws s3 ls "s3://${AWS_BACKUP_ACCOUNT_S3_BUCKET_NAME}/" | sort | tail -n 1 | awk '{print $4}')
aws s3 ls "s3://${AWS_BACKUP_ACCOUNT_S3_BUCKET_NAME}/" | awk '{print $4}' | grep -v "$LATEST_BACKUP" | while read -r OBJECT; do
    echo "Deleting $OBJECT..."
    aws s3 rm "s3://${AWS_BACKUP_ACCOUNT_S3_BUCKET_NAME}/$OBJECT"
done

# Upload the new backup to S3
echo "Uploading new backup to S3..."
aws s3 cp "/tmp/$ARCHIVE_NAME" "s3://${AWS_BACKUP_ACCOUNT_S3_BUCKET_NAME}/$ARCHIVE_NAME"

# Clean up local temporary files
echo "Cleaning up local files..."
rm -rf "$BACKUP_DIR"
rm "/tmp/$ARCHIVE_NAME"

echo "Backup completed successfully."
