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

# Find the latest backup in the Restic repository using both tags
echo "Finding the latest backup snapshot for $SYNAPSE_SERVER_DOMAIN_NAME..."
LATEST_SNAPSHOT=$(restic -r "$RESTIC_REPOSITORY" snapshots --tag "$SYNAPSE_SERVER_DOMAIN_NAME" --json | jq -r 'max_by(.time) | .short_id')

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

# Stop Synapse and Signal bridge to prevent corruption during restore
echo "Stopping Synapse container..."
docker-compose -f /matrix-synapse/docker-compose.yml down

echo "Stopping Signal bridge container..."
docker stop mautrix-signal || true
docker rm mautrix-signal || true

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

# Restore SQLite database for Synapse
echo "Restoring Synapse SQLite database..."
cp "$EXTRACTED_DIR/homeserver.db.backup" /matrix-synapse/data/homeserver.db

# Restore secrets for Synapse from the backup, replacing any existing values in homeserver.yaml
SECRETS_BACKUP_FILE="$EXTRACTED_DIR/synapse_secrets.backup"
if [ -f "$SECRETS_BACKUP_FILE" ]; then
    echo "Restoring Synapse secrets from $SECRETS_BACKUP_FILE to homeserver.yaml..."
    
    # Use sed to replace secrets in homeserver.yaml with those in the backup file
    sed -i -e "/^registration_shared_secret:/d" \
           -e "/^macaroon_secret_key:/d" \
           -e "/^form_secret:/d" \
           -e "/^turn_shared_secret:/d" /matrix-synapse/data/homeserver.yaml

    cat "$SECRETS_BACKUP_FILE" >> /matrix-synapse/data/homeserver.yaml
else
    echo "Warning: Synapse secrets backup file not found. Skipping secrets restoration."
fi

# Restore Signal bridge database
SIGNAL_BRIDGE_DB_BACKUP="$EXTRACTED_DIR/mautrix_signal.db.backup"
SIGNAL_BRIDGE_DB="/matrix-synapse/mautrix-signal/mautrix_signal.db"
if [ -f "$SIGNAL_BRIDGE_DB_BACKUP" ]; then
    echo "Restoring Signal bridge database..."
    cp "$SIGNAL_BRIDGE_DB_BACKUP" "$SIGNAL_BRIDGE_DB"
else
    echo "Warning: Signal bridge database backup file not found. Skipping Signal bridge database restoration."
fi

# Restore Signal bridge secrets
SIGNAL_BRIDGE_SECRETS_BACKUP="$EXTRACTED_DIR/signal_secrets.backup"
SIGNAL_BRIDGE_CONFIG="/matrix-synapse/mautrix-signal/config.yaml"
if [ -f "$SIGNAL_BRIDGE_SECRETS_BACKUP" ]; then
    echo "Restoring Signal bridge secrets from $SIGNAL_BRIDGE_SECRETS_BACKUP to config.yaml..."
    
    # Use sed to remove existing tokens and replace them with restored secrets
    sed -i -e "/^as_token:/d" \
           -e "/^hs_token:/d" "$SIGNAL_BRIDGE_CONFIG"

    cat "$SIGNAL_BRIDGE_SECRETS_BACKUP" >> "$SIGNAL_BRIDGE_CONFIG"
else
    echo "Warning: Signal bridge secrets backup file not found. Skipping Signal bridge secrets restoration."
fi

# Set proper permissions on the restored data
echo "Setting proper permissions for /matrix-synapse/data..."
chown -R 991:991 /matrix-synapse/data
if [ $? -ne 0 ]; then
    echo "Error: Failed to set permissions on restored data."
    exit 1
fi

# Start the Synapse container
echo "Starting Synapse container..."
docker-compose -f /matrix-synapse/docker-compose.yml up -d
if [ $? -ne 0 ]; then
    echo "Error: Failed to start Synapse. Please check Docker services."
    exit 1
fi
echo "Synapse container started successfully."

# Start the Signal bridge container
echo "Starting Signal bridge container..."
docker run -d --name mautrix-signal \
    -v $SIGNAL_BRIDGE_DIR:/data \
    dock.mau.dev/mautrix/signal:latest

# Clean up restore files
echo "Cleaning up restore files in $RESTORE_DIR..."
rm -rf "$RESTORE_DIR"

# Clean up environment variables for security
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset RESTIC_PASSWORD

echo "Restore from the latest backup completed successfully."
