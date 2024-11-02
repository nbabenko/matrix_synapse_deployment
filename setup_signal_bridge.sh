#!/bin/bash

# Define the directory for the Signal bridge
SIGNAL_BRIDGE_DIR="/matrix-synapse/mautrix-signal"
APP_SERVICE_DIR="/matrix-synapse/appservices"

# Create necessary directories
mkdir -p $SIGNAL_BRIDGE_DIR
mkdir -p $APP_SERVICE_DIR

# Pull the Signal bridge Docker image
docker pull dock.mau.dev/mautrix/signal:latest

# Generate the registration.yaml file if it doesn’t exist
if [ ! -f $SIGNAL_BRIDGE_DIR/registration.yaml ]; then
  echo "Generating Signal bridge registration.yaml..."
  docker run --rm -v $SIGNAL_BRIDGE_DIR:/data dock.mau.dev/mautrix/signal:latest -g
fi

# Move registration.yaml to Synapse appservices directory if not already moved
if [ ! -f $APP_SERVICE_DIR/registration.yaml ]; then
  mv $SIGNAL_BRIDGE_DIR/registration.yaml $APP_SERVICE_DIR/
fi

# Ensure app_service_config_files entry exists in Synapse configuration
if ! grep -q "app_service_config_files:" /matrix-synapse/data/homeserver.yaml; then
  echo "Adding Signal bridge to Synapse app service configuration..."
  echo "app_service_config_files:" >> /matrix-synapse/data/homeserver.yaml
  echo "  - /matrix-synapse/appservices/registration.yaml" >> /matrix-synapse/data/homeserver.yaml
fi

# Configure Signal bridge if config.yaml doesn’t exist
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

# Start the Signal bridge in Docker
echo "Starting Signal bridge container..."
docker run -d --name mautrix-signal \
    -v $SIGNAL_BRIDGE_DIR:/data \
    dock.mau.dev/mautrix/signal:latest

# Completion message
echo "Signal bridge setup completed. Verify by checking Synapse and Signal bridge logs."

# Optional: Uncomment to view logs immediately
# docker logs -f synapse &
# docker logs -f mautrix-signal &
