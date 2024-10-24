#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status

# Load variables from the config file
source /matrix-synapse/server_config.sh

# Install coturn if not already installed
echo "Installing coturn..."
apt-get install -y coturn

# Create copies of the TLS certificate and key for coturn
echo "Creating copies of the TLS certificate and key for coturn..."
cp /matrix-synapse/data/certificate.crt /matrix-synapse/data/coturn_certificate.crt
cp /matrix-synapse/data/tls.key /matrix-synapse/data/coturn_tls.key

# Set permissions for the copied TLS certificate and key to be accessible by coturn
chmod 644 /matrix-synapse/data/coturn_certificate.crt
chmod 640 /matrix-synapse/data/coturn_tls.key
chown root:turnserver /matrix-synapse/data/coturn_tls.key /matrix-synapse/data/coturn_certificate.crt

# Get the public IP address dynamically
PUBLIC_IP=$(curl -s https://api.ipify.org)

# Configure coturn
COTURN_CONFIG_FILE="/etc/turnserver.conf"
echo "Configuring coturn at $COTURN_CONFIG_FILE..."

cat <<EOT > $COTURN_CONFIG_FILE
listening-port=3478
fingerprint
use-auth-secret
static-auth-secret=$TURN_SHARED_SECRET
realm=$SYNAPSE_SERVER_DOMAIN_NAME
total-quota=100
bps-capacity=0
stale-nonce=600
log-file=/var/tmp/turn.log
cli-password=${TURN_SHARED_SECRET:-defaultpassword}
cert=/matrix-synapse/data/coturn_certificate.crt
pkey=/matrix-synapse/data/coturn_tls.key
tls-listening-port=5349

# Add external-ip for public IP address for Coturn
external-ip=$PUBLIC_IP
EOT

# Ensure coturn service is running
echo "Starting coturn service..."
service coturn restart || echo "Warning: Failed to restart coturn service, please check manually."

# Configure UFW to allow coturn traffic
echo "Configuring UFW to allow coturn traffic..."
ufw allow 3478/tcp
ufw allow 3478/udp
ufw allow 5349/tcp
ufw allow 5349/udp

# Enable UFW
ufw --force enable

# Update homeserver.yaml for Synapse to use TURN server
HOMESERVER_CONFIG_FILE="/matrix-synapse/data/homeserver.yaml"
echo "Updating homeserver.yaml at $HOMESERVER_CONFIG_FILE..."

cat <<EOT >> $HOMESERVER_CONFIG_FILE

# TURN server configuration
turn_uris:
  - "turn:$PUBLIC_IP:3478?transport=udp"
  - "turn:$PUBLIC_IP:3478?transport=tcp"
turn_shared_secret: "$TURN_SHARED_SECRET"
turn_user_lifetime: "1h"
turn_allow_guests: true
EOT

# Summary
echo "Coturn installation and configuration, and Synapse homeserver.yaml update completed successfully."
