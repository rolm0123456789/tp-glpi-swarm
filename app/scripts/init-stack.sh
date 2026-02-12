#!/bin/bash
# Script exécuté sur le Manager VM

# 1. Création des secrets
echo "Creation des secrets..."

if ! docker secret inspect db_root_password >/dev/null 2>&1; then
    echo "Génération du mot de passe root..."
    openssl rand -base64 20 | docker secret create db_root_password -
else
    echo "Le secret db_root_password existe déjà."
fi

if ! docker secret inspect db_password >/dev/null 2>&1; then
    echo "Génération du mot de passe glpi..."
    openssl rand -base64 20 | docker secret create db_password -
else
    echo "Le secret db_password existe déjà."
fi

# 2. Création des dossiers partagés via NFS (monté sur /mnt/shared)
mkdir -p /mnt/shared/glpi_data
mkdir -p /mnt/shared/mysql_data
mkdir -p /mnt/shared/certbot_conf
mkdir -p /mnt/shared/certbot_www
mkdir -p /mnt/shared/nginx_conf/conf.d

echo "Copying nginx config to NFS..."
cp /home/vagrant/nginx/nginx.conf /mnt/shared/nginx_conf/nginx.conf
cp /home/vagrant/nginx/conf.d/* /mnt/shared/nginx_conf/conf.d/

# 3. Déploiement de la stack
echo "Deploiement de la stack..."
cd /home/vagrant
docker stack deploy -c docker-stack.yml glpi_stack