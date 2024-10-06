# Ensure correct permissions on TLS certificate and key
echo "Setting permissions on TLS certificate and key..."
chmod 644 /matrix-synapse/data/certificate.crt
chmod 600 /matrix-synapse/data/tls.key
chown 991:991 /matrix-synapse/data/certificate.crt
chown 991:991 /matrix-synapse/data/tls.key