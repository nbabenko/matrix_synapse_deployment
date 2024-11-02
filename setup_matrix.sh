#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

chmod +x /matrix-synapse/server_config.sh
chmod +x /matrix-synapse/backup_matrix.sh
chmod +x /matrix-synapse/restore_from_backup.sh

# Load variables from the config file
source /matrix-synapse/server_config.sh

# Add authorized SSH keys if specified
if [ -n "$ADDITIONAL_SSH_KEYS_TO_AUTHORIZE" ]; then
    echo "Adding additional SSH keys to authorized_keys..."
    mkdir -p ~/.ssh
    echo "$ADDITIONAL_SSH_KEYS_TO_AUTHORIZE" >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
fi

# Update and install required packages
echo "Updating package list and installing Docker, Curl, Rsync, and Vim..."
apt-get update -y
apt-get upgrade -y
apt-get install -y docker.io curl rsync vim unzip cron nginx ssmtp restic jq coturn ufw net-tools ntp ntpdate

# Configure UFW firewall settings
echo "Configuring UFW firewall to allow necessary ports and deny others..."
ufw default deny incoming
ufw default allow outgoing

# Allow SSH (port 22)
ufw allow 22/tcp

# Allow HTTP (port 80) and HTTPS (port 443) for web traffic
ufw allow 80/tcp
ufw allow 443/tcp

# Allow Synapse HTTP and Federation ports (8008 and 8448)
ufw allow 8008/tcp
ufw allow 8448/tcp

# Enable UFW
ufw --force enable

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
sed -i '/^server_name:/a tls_certificate_path: "/data/certificate.crt"\ntls_private_key_path: "/data/tls.key"' /matrix-synapse/data/homeserver.yaml

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

# Conditionally modify homeserver.yaml to keep history indefinitely
if [ "$USE_SELF_SIGNED_SSL" = true ]; then
  echo "Installing Certbot to automatically obtain and renew SSL certificates..."
  apt-get install -y certbot python3-certbot-nginx

  echo "Configuring temporary NGINX for Let's Encrypt challenge..."
  cat <<EOL > /etc/nginx/sites-available/letsencrypt
server { 
  listen 80; server_name ${SYNAPSE_SERVER_DOMAIN_NAME};
  location /.well-known/acme-challenge/ {
      root /var/www/html;
  }
  location / {
      return 404;
  }
}
EOL

  ln -s /etc/nginx/sites-available/letsencrypt /etc/nginx/sites-enabled/
  
  echo "Restarting nginx"
  nginx -t && (pgrep nginx > /dev/null && nginx -s reload || nginx)
  echo "Nginx restarted."

  /bin/bash /matrix-synapse/generate_self_signed_certificate.sh

else
  # Combine server certificate and intermediate certificates to create fullchain certificate
  echo "Creating fullchain certificate by combining server and intermediate certificates..."
  cat /matrix-synapse/data/tls.crt /matrix-synapse/data/ca-bundle.ca-bundle > /matrix-synapse/data/certificate.crt
fi

/bin/bash /matrix-synapse/set_certificate_permissions.sh

# Setup Coturn server for VoIP calls
/bin/bash /matrix-synapse/setup_coturn.sh

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

# Setup signal bridge
/bin/bash /matrix-synapse/setup_signal_bridge.sh

# Start synapse container
/bin/bash /matrix-synapse/container_up.sh

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

    ssl_certificate /matrix-synapse/data/certificate.crt;
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

if [ "$USE_SELF_SIGNED_SSL" = true ]; then
    if [ -f /etc/nginx/sites-enabled/letsencrypt ]; then
      rm /etc/nginx/sites-enabled/letsencrypt
    fi

    # Add a cron job to regenerate the SSL certificate every 2 months at 1:00 AM UTC
    echo "Setting up a cron job for regular SSL certificate regeneration..."
    (crontab -l 2>/dev/null | grep -v "/bin/bash /matrix-synapse/generate_self_signed_certificate.sh"; echo "0 3 1 */2 * echo \"Certificate generation started at \$(date)\" >> $LOG_FILE; /bin/bash /matrix-synapse/generate_self_signed_certificate.sh >> $LOG_FILE 2>&1; if [ \$? -eq 0 ]; then echo \"Certificate successfully renewed on \$(date)\" >> $LOG_FILE; echo -e \"To: $ALERT_EMAIL\nFrom: no-reply@$SYNAPSE_SERVER_DOMAIN_NAME\nSubject: Certificate successfully renewed\n\nThe SSL certificate was successfully renewed on \$(date).\" | ssmtp $ALERT_EMAIL; else echo \"Error renewing the SSL certificate on \$(date)\" >> $LOG_FILE; echo -e \"To: $ALERT_EMAIL\nFrom: no-reply@$SYNAPSE_SERVER_DOMAIN_NAME\nSubject: Error renewing the SSL certificate\n\nError renewing the SSL certificate on \$(date). Please check the Synapse server.\" | ssmtp $ALERT_EMAIL; fi") | crontab - || echo "Failed to add the cron job"
fi

# Enable the NGINX configuration
ln -s /etc/nginx/sites-available/matrix-synapse /etc/nginx/sites-enabled/
# Reload NGINX
echo "Restarting nginx"
nginx -t && (pgrep nginx > /dev/null && nginx -s reload || nginx)
echo "Nginx restarted."

echo "Setting up cron job for regular backups..."

# Add a cron job to run backup_matrix.sh every night at 1:00 AM UTC
(crontab -l 2>/dev/null | grep -v "backup_matrix.sh"; echo "0 1 * * * echo \"Backup started at \$(date)\" >> $LOG_FILE; /bin/bash /matrix-synapse/backup_matrix.sh >> $LOG_FILE 2>&1; echo \"Backup finished at \$(date)\" >> $LOG_FILE") | crontab - || echo "Failed to add cron job"

echo -e "To: $ALERT_EMAIL\nFrom: no-reply@$SYNAPSE_SERVER_DOMAIN_NAME\nSubject: Matrix Synapse Server Setup Completed\n\nMatrix Synapse Server Setup Completed Successfully." | ssmtp $ALERT_EMAIL

service cron start

echo "Cron job added. The backup will run every night at 2:00 AM CET."

