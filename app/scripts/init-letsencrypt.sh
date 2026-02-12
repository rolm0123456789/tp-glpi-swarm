#!/bin/bash

# Configuration
DOMAINS="glpi.local" # Remplacez par votre vrai domaine ou laissez localhost pour test si DNS configuré
EMAIL="admin@example.com"
STAGING=1 # Set to 1 for testing, 0 for production

echo "Attente du démarrage des services..."
sleep 20

echo "Lancement de la génération de certificat SSL..."

# 1. Demande de certificat via Certbot (Webroot mode)
# On utilise le container 'certbot' défini dans la stack, ou on lance un éphémère.
# Comme on est sur le manager avec docker, on peut exec dans le container certbot s'il tourne, ou run --rm. 
# Le container certbot dans la stack dort (sleep infinity). On va l'utiliser.

MAX_RETRIES=30
echo "Attente du conteneur certbot..."
for i in $(seq 1 $MAX_RETRIES); do
    CONTAINER_ID=$(docker ps -q -f name=glpi_stack_certbot)
    if [ -n "$CONTAINER_ID" ]; then
        echo "Conteneur trouvé : $CONTAINER_ID"
        break
    fi
    echo "En attente du conteneur certbot... ($i/$MAX_RETRIES)"
    sleep 5
done

if [ -z "$CONTAINER_ID" ]; then
    echo "Erreur: Timeout - Container certbot introuvable après $((MAX_RETRIES*5)) secondes."
    exit 1
fi

if [ "$STAGING" != "0" ]; then
    STAGING_ARG="--staging"
fi

echo "Execution de certbot..."
set +e
docker exec $CONTAINER_ID certbot certonly --webroot -w /var/www/certbot \
    $STAGING_ARG \
    -d $DOMAINS \
    --email $EMAIL \
    --rsa-key-size 4096 \
    --agree-tos \
    --force-renewal \
    --non-interactive
CERTBOT_EXIT_CODE=$?
set -e

if [ $CERTBOT_EXIT_CODE -ne 0 ]; then
    echo "⚠️ Certbot a échoué (probablement car $DOMAINS est local ou inaccessible)."
    echo "Génération d'un certificat auto-signé pour débloquer le HTTPS..."
    
    mkdir -p /mnt/shared/certbot_conf/live/$DOMAINS
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /mnt/shared/certbot_conf/live/$DOMAINS/privkey.pem \
        -out /mnt/shared/certbot_conf/live/$DOMAINS/fullchain.pem \
        -subj "/C=FR/ST=Paris/L=Paris/O=GLPI/OU=IT/CN=$DOMAINS"
fi

# 2. Activation de la config SSL Nginx
echo "Activation de la configuration SSL..."
# On dé-commente la section SSL dans le fichier sur le NFS
sed -i 's/# SSL_START //g' /mnt/shared/nginx_conf/conf.d/glpi.conf
sed -i 's/# SSL_END //g' /mnt/shared/nginx_conf/conf.d/glpi.conf

# 3. Reload Nginx (sur tous les noeuds)
echo "Reloading Nginx services..."
# Comme c'est un service global, on peut forcer un update ou tenter un signal.
# Le plus simple en swarm sans accès direct aux autres nodes est de update le service
docker service update --force glpi_stack_nginx

echo "SSL mis en place avec succès !"
