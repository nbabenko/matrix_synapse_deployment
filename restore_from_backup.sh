#!/bin/bash

set -e

# Load variables from the config file
source /matrix-synapse/server_config.sh

RESTORE_DIR="/tmp/matrix-synapse-restore"
RESTIC_REPOSITORY="s3:s3.amazonaws.com/${AWS_BACKUP_ACCOUNT_S3_BUCKET_NAME}"
export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"

# Check if encryption is required based on config
if [ -n "$BACKUP_ENCRYPTION_PASSWORD" ]; then
    echo "Encryption enabled for restore."
    export RESTIC_PASSWORD="$BACKUP_ENCRYPTION_PASSWORD"
    ENCRYPTION_FLAG=""
else
    echo "No encryption enabled for restore."
    unset RESTIC_PASSWORD
    ENCRYPTION_FLAG="--no-encryption"
fi

# Find the latest backup in the Restic repository
echo "Finding the latest backup..."
LATEST_SNAPSHOT=$(restic -r "$RESTIC_REPOSITORY" snapshots --tag "synapse-backup" --json | jq -r 'sort_by(.time) | last(.[]).short_id')

# Check if any backups are available
if [ -z "$LATEST_SNAPSHOT" ]; then
    echo "No backups found in Restic repository."
    exit 1
fi

echo "Latest backup snapshot found: $LATEST_SNAPSHOT"

# Create restore directory
mkdir -p "$RESTORE_DIR"

# Restore the latest backup using Restic
echo "Restoring the latest backup from Restic..."
restic -r "$RESTIC_REPOSITORY" restore "$LATEST_SNAPSHOT" --target "$RESTORE_DIR" $ENCRYPTION_FLAG

# Stop Synapse to prevent corruption during restore
echo "Stopping Synapse..."
docker-compose -f /matrix-synapse/docker-compose.yml down

# Dynamically find the restored data directory
EXTRACTED_DIR="$RESTORE_DIR/matrix-synapse/data"

# Restore data directory
echo "Restoring data directory..."
rsync -a --delete "$EXTRACTED_DIR/" /matrix-synapse/data/

# Set proper permissions
chown -R 991:991 /matrix-synapse/data

# Start the Synapse container again
echo "Starting Synapse container..."
docker-compose -f /matrix-synapse/docker-compose.yml up -d

# Clean up restore files
echo "Cleaning up restore files..."
rm -rf "$RESTORE_DIR"

# Clean up environment variables
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset RESTIC_PASSWORD

echo "Restore from the latest backup completed successfully."
