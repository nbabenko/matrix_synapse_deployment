#!/bin/bash

# Define directories
SIGNAL_BRIDGE_DIR="/matrix-synapse/mautrix-signal"
APP_SERVICE_DIR="/matrix-synapse/data/appservices"

# Create necessary directories
mkdir -p $SIGNAL_BRIDGE_DIR
mkdir -p $APP_SERVICE_DIR

# Pull the Signal bridge Docker image
docker pull dock.mau.dev/mautrix/signal:latest

# Configure the Signal bridge if config.yaml doesn’t exist
if [ ! -f $SIGNAL_BRIDGE_DIR/config.yaml ]; then
  echo "Creating Signal bridge config.yaml..."
  cat <<EOL > $SIGNAL_BRIDGE_DIR/config.yaml
homeserver:
  address: "http://localhost:8008"             # Synapse URL; replace if different
  domain: "${SYNAPSE_SERVER_DOMAIN_NAME}"      # Synapse domain

appservice:
  as_token: "YOUR_AS_TOKEN"                    # Replace with secure token
  hs_token: "YOUR_HS_TOKEN"                    # Replace with secure token

database:
  type: sqlite3                                # Database type
  database: "/data/mautrix_signal.db"          # Database path

bridge:
  username_template: "signal_\${userid}"       # Optional username template
EOL
fi

# Generate the registration.yaml file
echo "Generating Signal bridge registration.yaml..."
docker run --rm -v $SIGNAL_BRIDGE_DIR:/data dock.mau.dev/mautrix/signal:latest /usr/bin/mautrix-signal -g

# Move registration.yaml to the appservices directory if not already there
if [ -f $SIGNAL_BRIDGE_DIR/registration.yaml ]; then
  echo "Moving registration.yaml to appservices directory..."
  mv -f $SIGNAL_BRIDGE_DIR/registration.yaml $APP_SERVICE_DIR/signal-registration.yaml
  chmod 644 $APP_SERVICE_DIR/signal-registration.yaml
  chown 991:991 $APP_SERVICE_DIR/signal-registration.yaml
else
  echo "Error: registration.yaml was not generated as expected."
  exit 1
fi

# Ensure app_service_config_files entry exists in Synapse configuration
if ! grep -q "app_service_config_files:" /matrix-synapse/data/homeserver.yaml; then
  echo "Adding app_service_config_files section to Synapse configuration..."
  echo "app_service_config_files:" >> /matrix-synapse/data/homeserver.yaml
fi

# Add the Signal bridge registration file to app_service_config_files if not already added
if ! grep -q "/data/appservices/signal-registration.yaml" /matrix-synapse/data/homeserver.yaml; then
  echo "  - /data/appservices/signal-registration.yaml" >> /matrix-synapse/data/homeserver.yaml
fi

# Start the Signal bridge container
echo "Starting Signal bridge container..."
docker run -d --name mautrix-signal \
    -v $SIGNAL_BRIDGE_DIR:/data \
    dock.mau.dev/mautrix/signal:latest

# Completion message
echo "Signal bridge setup completed. Verify by checking Synapse and Signal bridge logs."

# Optional: Uncomment to view logs immediately
# docker logs -f synapse &
# docker logs -f mautrix-signal &
