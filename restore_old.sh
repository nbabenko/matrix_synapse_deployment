#!/bin/bash

set -e

# Load variables from the config file
source /matrix-synapse/server_config.sh

RESTORE_DIR="/tmp/matrix-synapse-restore"

# Find the latest backup in S3
echo "Finding the latest backup..."
LATEST_BACKUP=$(aws s3 ls "s3://matrix.babenko.link.backup/" | sort | tail -n 1 | awk '{print $4}')

# Check if any backups are available
if [ -z "$LATEST_BACKUP" ]; then
    echo "No backups found in S3."
    exit 1
fi

echo "Latest backup found: $LATEST_BACKUP"

# Create restore directory
mkdir -p "$RESTORE_DIR"

# Download the latest backup from S3
echo "Downloading the latest backup from S3..."
aws s3 cp "s3://matrix.babenko.link.backup/$LATEST_BACKUP" "$RESTORE_DIR/$LATEST_BACKUP"

# Extract the backup
echo "Extracting the backup..."
tar -xzf "$RESTORE_DIR/$LATEST_BACKUP" -C "$RESTORE_DIR"

# Stop Synapse to prevent corruption during restore
echo "Stopping Synapse..."
docker-compose -f /matrix-synapse/docker-compose.yml down

# Dynamically find the extracted folder (assuming it is created under $RESTORE_DIR)
EXTRACTED_DIR=$(find "$RESTORE_DIR" -mindepth 1 -maxdepth 1 -type d | head -n 1)

# Restore data directory
echo "Restoring data directory..."
rsync -a --delete "$EXTRACTED_DIR/data/" /matrix-synapse/data/

# Copy the SQLite database back into the container
echo "Restoring SQLite database..."
cp "$EXTRACTED_DIR/homeserver.db" /matrix-synapse/data/homeserver.db

# Set proper permissions
chown -R 991:991 /matrix-synapse/data/homeserver.db

# Start the Synapse container again
echo "Starting Synapse container..."
docker-compose -f /matrix-synapse/docker-compose.yml up -d

# Installing SQLite in the Synapse container for future use, same as in setup_matrix.sh
echo "Installing SQLite in the Synapse container..."
docker exec synapse apt-get update
docker exec synapse apt-get install -y sqlite3

# Clean up restore files
echo "Cleaning up restore files..."
rm -rf "$RESTORE_DIR"

echo "Restore from latest backup completed successfully."