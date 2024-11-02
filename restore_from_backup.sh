#!/bin/bash

set -e

# Load variables from the config file
source /matrix-synapse/server_config.sh

RESTORE_DIR="/tmp/matrix-synapse-restore"
RESTIC_REPOSITORY="s3:s3.amazonaws.com/${AWS_BACKUP_ACCOUNT_S3_BUCKET_NAME}"
export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
export RESTIC_PASSWORD="$BACKUP_ENCRYPTION_PASSWORD"
export AWS_DEFAULT_REGION="$AWS_BUCKET_REGION"

# Check if the Restic repository is accessible
echo "Verifying access to Restic repository..."
if ! restic -r "$RESTIC_REPOSITORY" snapshots > /dev/null 2>&1; then
    echo "Error: Unable to access the Restic repository. Please check AWS credentials or repository configuration."
    exit 1
fi

# Find the latest backup in the Restic repository
echo "Finding the latest backup snapshot..."
LATEST_SNAPSHOT=$(restic -r "$RESTIC_REPOSITORY" snapshots --tag "synapse-backup" --json | jq -r 'max_by(.time) | .short_id')

# Check if any backups are available
if [ -z "$LATEST_SNAPSHOT" ]; then
    echo "No backups found in the Restic repository."
    exit 1
fi

echo "Latest backup snapshot found: $LATEST_SNAPSHOT"

# Create the restore directory
mkdir -p "$RESTORE_DIR"

# Restore the latest backup using Restic
echo "Restoring the latest backup from Restic to $RESTORE_DIR..."
restic -r "$RESTIC_REPOSITORY" restore "$LATEST_SNAPSHOT" --target "$RESTORE_DIR"
if [ $? -ne 0 ]; then
    echo "Error: Failed to restore the backup."
    exit 1
fi
echo "Restore completed successfully to $RESTORE_DIR."

# Stop Synapse to prevent corruption during restore
echo "Stopping Synapse..."
docker-compose -f /matrix-synapse/docker-compose.yml down
if [ $? -ne 0 ]; then
    echo "Error: Failed to stop Synapse. Please check Docker services."
    exit 1
fi

# Dynamically find the restored data directory (typically under the restore directory)
EXTRACTED_DIR="$RESTORE_DIR/matrix-synapse/data"

# Verify if the restored data directory exists
if [ ! -d "$EXTRACTED_DIR" ]; then
    echo "Error: Restored data directory $EXTRACTED_DIR not found."
    exit 1
fi

# Restore data directory
echo "Restoring data directory from $EXTRACTED_DIR to /matrix-synapse/data/..."
rsync -a "$EXTRACTED_DIR/" /matrix-synapse/data/
if [ $? -ne 0 ]; then
    echo "Error: Failed to copy restored data to target directory."
    exit 1
fi
echo "Data directory restored successfully."

# Restore SQLite database
echo "Restoring SQLite database..."
cp "$EXTRACTED_DIR/homeserver.db.backup" /matrix-synapse/data/homeserver.db

# Restore secrets from the backup, replacing any existing values in homeserver.yaml
SECRETS_BACKUP_FILE="$EXTRACTED_DIR/synapse_secrets.backup"
if [ -f "$SECRETS_BACKUP_FILE" ]; then
    echo "Restoring secrets from $SECRETS_BACKUP_FILE to homeserver.yaml..."

    # Use sed to replace secrets in homeserver.yaml with those in the backup file
    sed -i -e "/^registration_shared_secret:/d" \
           -e "/^macaroon_secret_key:/d" \
           -e "/^form_secret:/d" \
           -e "/^turn_shared_secret:/d" /matrix-synapse/data/homeserver.yaml

    cat "$SECRETS_BACKUP_FILE" >> /matrix-synapse/data/homeserver.yaml
else
    echo "Warning: Secrets backup file not found. Skipping secrets restoration."
fi

# Set proper permissions on the restored data
echo "Setting proper permissions for /matrix-synapse/data..."
chown -R 991:991 /matrix-synapse/data
if [ $? -ne 0 ]; then
    echo "Error: Failed to set permissions on restored data."
    exit 1
fi

# Start the Synapse container again
echo "Starting Synapse container..."
docker-compose -f /matrix-synapse/docker-compose.yml up -d
if [ $? -ne 0 ]; then
    echo "Error: Failed to start Synapse. Please check Docker services."
    exit 1
fi
echo "Synapse container started successfully."

# Start synapse container
/bin/bash /matrix-synapse/container_up.sh

# Clean up restore files
echo "Cleaning up restore files in $RESTORE_DIR..."
rm -rf "$RESTORE_DIR"

# Clean up environment variables for security
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset RESTIC_PASSWORD

echo "Restore from the latest backup completed successfully."
