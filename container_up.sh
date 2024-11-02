# Start Synapse service using Docker Compose
echo "Starting Synapse container..."
docker-compose -f /matrix-synapse/docker-compose.yml up -d
if [ $? -ne 0 ]; then
    echo "Error: Failed to start Synapse. Please check Docker services."
    exit 1
fi
echo "Synapse container started successfully."
