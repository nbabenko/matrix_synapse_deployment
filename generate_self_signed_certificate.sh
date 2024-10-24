set -e

# Load variables from the config file
source /matrix-synapse/server_config.sh

echo "Obtaining SSL certificate from Let's Encrypt..."
certbot certonly --webroot -w /var/www/html --server https://api.buypass.com/acme/directory -d ${SYNAPSE_SERVER_DOMAIN_NAME} --non-interactive --agree-tos -m ${ALERT_EMAIL}

# Check if the certificate was successfully obtained
if [ ! -f /etc/letsencrypt/live/${SYNAPSE_SERVER_DOMAIN_NAME}/fullchain.pem ]; then
    echo "Failed to obtain SSL certificate from Let's Encrypt."
    exit 1
fi
cp -L /etc/letsencrypt/live/${SYNAPSE_SERVER_DOMAIN_NAME}/fullchain.pem /matrix-synapse/data/certificate.crt
cp -L /etc/letsencrypt/live/${SYNAPSE_SERVER_DOMAIN_NAME}/privkey.pem /matrix-synapse/data/tls.key

echo "SSL certificate successfully generated."

/bin/bash /matrix-synapse/set_certificate_permissions.sh

echo "Checking if docker is available and synapse is running to restart synapse"
command -v docker > /dev/null && docker ps | grep synapse && docker restart synapse
echo "Synapse restarted."

echo "Restarting nginx"
nginx -t && (pgrep nginx > /dev/null && nginx -s reload || nginx)
echo "Nginx restarted."


