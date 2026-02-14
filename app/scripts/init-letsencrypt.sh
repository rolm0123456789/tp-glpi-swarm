#!/bin/bash
set -e

# =============================================
#  Script de configuration SSL / Let's Encrypt
#  Exécuté sur le noeud Manager
# =============================================

# Configuration
DOMAINS="glpi.local"
EMAIL="admin@example.com"
STAGING=1  # 1 = staging (test), 0 = production

echo "========================================="
echo "  Configuration SSL - Let's Encrypt"
echo "========================================="

echo "[1/4] Attente du démarrage des services..."
sleep 20

# Attente du conteneur Certbot
echo "[2/4] Recherche du conteneur Certbot..."
MAX_RETRIES=30
CONTAINER_ID=""
for i in $(seq 1 $MAX_RETRIES); do
    CONTAINER_ID=$(docker ps -q -f name=glpi_stack_certbot 2>/dev/null)
    if [ -n "$CONTAINER_ID" ]; then
        echo "  -> Conteneur Certbot trouvé : $CONTAINER_ID"
        break
    fi
    echo "  En attente... ($i/$MAX_RETRIES)"
    sleep 5
done

if [ -z "$CONTAINER_ID" ]; then
    echo "ERREUR: Conteneur Certbot introuvable après $((MAX_RETRIES * 5))s."
    echo "Génération d'un certificat auto-signé en fallback..."
    sudo mkdir -p /mnt/shared/certbot_conf/live/$DOMAINS
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /mnt/shared/certbot_conf/live/$DOMAINS/privkey.pem \
        -out /mnt/shared/certbot_conf/live/$DOMAINS/fullchain.pem \
        -subj "/C=FR/ST=IDF/L=Paris/O=GLPI-Swarm/OU=IT/CN=$DOMAINS"
else
    # Tentative de certificat Let's Encrypt
    echo "[3/4] Tentative de certificat Let's Encrypt..."
    STAGING_ARG=""
    if [ "$STAGING" != "0" ]; then
        STAGING_ARG="--staging"
    fi

    set +e
    docker exec "$CONTAINER_ID" certbot certonly --webroot -w /var/www/certbot \
        $STAGING_ARG \
        -d "$DOMAINS" \
        --email "$EMAIL" \
        --rsa-key-size 4096 \
        --agree-tos \
        --force-renewal \
        --non-interactive 2>&1
    CERTBOT_EXIT=$?
    set -e

    if [ $CERTBOT_EXIT -ne 0 ]; then
        echo "  Let's Encrypt a échoué (domaine local/inaccessible)."
        echo "  Génération d'un certificat auto-signé..."
        sudo mkdir -p /mnt/shared/certbot_conf/live/$DOMAINS
        sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout /mnt/shared/certbot_conf/live/$DOMAINS/privkey.pem \
            -out /mnt/shared/certbot_conf/live/$DOMAINS/fullchain.pem \
            -subj "/C=FR/ST=IDF/L=Paris/O=GLPI-Swarm/OU=IT/CN=$DOMAINS"
    else
        echo "  -> Certificat Let's Encrypt obtenu !"
    fi
fi

# Activation de la configuration SSL dans Nginx
echo "[4/4] Activation de la configuration SSL Nginx..."
# Décommenter les blocs SSL
sudo sed -i 's/# SSL_START //g' /mnt/shared/nginx_conf/conf.d/glpi.conf
# Supprimer le bloc proxy HTTP "avant SSL" (remplacé par la redirection HTTPS)
sudo sed -i '/# Proxy vers GLPI (mode HTTP/,/^    }$/d' /mnt/shared/nginx_conf/conf.d/glpi.conf

# Reload Nginx via un force-update du service Swarm (detach pour ne pas bloquer)
echo "  Rechargement de Nginx..."
docker service update --force --detach glpi_stack_nginx 2>/dev/null || true

echo ""
echo "========================================="
echo "  SSL configuré avec succès !"
echo "========================================="
echo "  -> HTTPS disponible sur le port 443"
echo "  -> HTTP redirige vers HTTPS"
echo ""
