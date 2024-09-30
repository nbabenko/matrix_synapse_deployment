#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

chmod +x /matrix-synapse/server_config.sh
chmod +x /matrix-synapse/backup_matrix.sh

# Load variables from the config file
source /matrix-synapse/server_config.sh

# Update and install required packages
echo "Updating package list and installing Docker, Curl, Rsync, and Vim..."
apt-get update -y
apt-get install -y docker.io curl rsync vim unzip cron nginx ssmtp

# Start Docker service
echo "Starting Docker service..."
systemctl start docker || service docker start || dockerd &

# Wait for Docker to be ready
sleep 10

# Install Docker Compose
echo "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/download/v2.20.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Verify Docker Compose installation
docker-compose version

# Install AWS CLI
echo "Installing AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
./aws/install

# Verify AWS CLI installation
aws --version

# Create necessary directories
echo "Creating directories for Matrix Synapse..."
mkdir -p /matrix-synapse/data

# Generate the Synapse configuration using Docker
echo "Generating Synapse configuration..."
docker run --rm -v /matrix-synapse/data:/data -e SYNAPSE_SERVER_NAME=${SYNAPSE_SERVER_DOMAIN_NAME} -e SYNAPSE_REPORT_STATS=yes matrixdotorg/synapse:latest generate

# Add the public_baseurl to the homeserver.yaml after the server_name line
echo "Adding public_baseurl configuration..."
sed -i "/^server_name:/a\public_baseurl: \"https://$SYNAPSE_SERVER_DOMAIN_NAME/\"" /matrix-synapse/data/homeserver.yaml

# Add bind_addresses to port 8008 listener for HTTP binding
echo "Adding bind_addresses to port 8008 listener for HTTP binding..."
sed -i '/port: 8008/a \    bind_addresses: ["0.0.0.0"]' /matrix-synapse/data/homeserver.yaml

# Add SSL listener configuration for federation on port 8448
echo "Adding SSL listener configuration..."
sed -i '/^listeners:/a\  - port: 8448\n    tls: true\n    bind_addresses: ["0.0.0.0"]\n    type: http\n    resources:\n      - names: [federation]' /matrix-synapse/data/homeserver.yaml

# Update TLS certificate and key paths in homeserver.yaml
echo "Updating TLS certificate and key paths in homeserver.yaml..."
sed -i '/^server_name:/a tls_certificate_path: "/data/fullchain.pem"\ntls_private_key_path: "/data/tls.key"' /matrix-synapse/data/homeserver.yaml

# Conditionally modify homeserver.yaml to keep history indefinitely
if [ "$KEEP_HISTORY_FOREVER" = true ]; then
  echo "Modifying homeserver.yaml to retain message history and media files..."
  cat <<EOL >> /matrix-synapse/data/homeserver.yaml

# Disable message retention policies (keep all messages)
retention:
  enabled: false

# Disable background purge jobs (keep all events)
purge_jobs:
  - enabled: false

# Retain media files indefinitely
media_storage:
  max_lifetime_ms: 0

# Increase Max upload size for the personal data
max_upload_size: 5368709120  # 5 GB in bytes
EOL
else
  echo "KEEP_HISTORY_FOREVER is set to false. No changes made to homeserver.yaml for history retention."
fi

# Combine server certificate and intermediate certificates to create fullchain.pem
echo "Creating fullchain.pem by combining server and intermediate certificates..."
cat /matrix-synapse/data/tls.crt /matrix-synapse/data/ca-bundle.ca-bundle > /matrix-synapse/data/fullchain.pem

# Ensure correct permissions on TLS certificate, key, and fullchain.pem
echo "Setting permissions on TLS certificate, key, and fullchain.pem..."
chmod 644 /matrix-synapse/data/fullchain.pem
chmod 600 /matrix-synapse/data/tls.key
chown 991:991 /matrix-synapse/data/fullchain.pem
chown 991:991 /matrix-synapse/data/tls.key

# Create Docker Compose file for Synapse with host networking
echo "Writing Docker Compose configuration..."
cat <<EOL > /matrix-synapse/docker-compose.yml
version: "3"
services:
  synapse:
    image: matrixdotorg/synapse:latest
    container_name: synapse
    restart: unless-stopped
    volumes:
      - ./data:/data
    network_mode: "host"
EOL

# Start Synapse service using Docker Compose
echo "Starting Synapse using Docker Compose..."
cd /matrix-synapse && docker-compose up -d

# Install SQLite in the Synapse container
echo "Installing SQLite in the Synapse container..."
docker exec synapse apt-get update
docker exec synapse apt-get install -y sqlite3

# --- SSMTP configuration ---
echo "Setting up SSMTP configuration..."
cat <<EOL > /etc/ssmtp/ssmtp.conf
root=${EMAIL_FROM}
mailhub=smtp.gmail.com:587
hostname=${SYNAPSE_SERVER_DOMAIN_NAME}
AuthUser=${EMAIL_FROM}
AuthPass=${EMAIL_PASSWORD}  # Replace this with your actual app password or email password
UseSTARTTLS=YES
TLS_CA_FILE=/matrix-synapse/data/tls.crt
AuthMethod=LOGIN
FromLineOverride=YES
EOL

# Create NGINX configuration for HTTPS
echo "Configuring NGINX for HTTPS..."
cat <<EOL > /etc/nginx/sites-available/matrix-synapse
server {
    listen 80;
    server_name ${SYNAPSE_SERVER_DOMAIN_NAME};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${SYNAPSE_SERVER_DOMAIN_NAME};

    ssl_certificate /matrix-synapse/data/fullchain.pem;
    ssl_certificate_key /matrix-synapse/data/tls.key;

    # Allow larger file uploads
    client_max_body_size 5G;

    location / {
        proxy_pass http://localhost:8008;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL

# -------------------------------------
# Setup cron job for regular backups
# -------------------------------------
echo "Setting up cron job for regular backups..."

# Enable the NGINX configuration
ln -s /etc/nginx/sites-available/matrix-synapse /etc/nginx/sites-enabled/
nginx -t && service nginx restart

echo -e "To: $ALERT_EMAIL\nFrom: no-reply@$SYNAPSE_SERVER_DOMAIN_NAME\nSubject: Matrix Synapse Server Setup Completed\n\nMatrix Synapse Server Setup Completed Successfully." | ssmtp $ALERT_EMAIL

# Add a cron job to run backup_matrix.sh every night at 2:00 AM CET
(crontab -l 2>/dev/null | grep -v "backup_matrix.sh"; echo "0 2 * * * echo \"Backup started at \$(date)\" >> $LOG_FILE; /bin/bash /matrix-synapse/backup_matrix.sh >> $LOG_FILE 2>&1; echo \"Backup finished at \$(date)\" >> $LOG_FILE") | crontab - || echo "Failed to add cron job"

echo "Cron job added. The backup will run every night at 2:00 AM CET."

