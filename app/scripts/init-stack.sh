#!/bin/bash
set -e

# =============================================
#  Script d'initialisation de la Stack GLPI
#  Exécuté sur le noeud Manager
# =============================================

echo "========================================="
echo "  Initialisation de la Stack GLPI"
echo "========================================="

# 1. Création des secrets Docker
echo "[1/4] Création des secrets Docker..."

DB_ROOT_PASS=""
DB_USER_PASS=""

if ! docker secret inspect db_root_password >/dev/null 2>&1; then
    DB_ROOT_PASS=$(openssl rand -base64 16 | tr -d '=+/')
    echo "$DB_ROOT_PASS" | docker secret create db_root_password -
    echo "  -> Secret db_root_password créé."
else
    echo "  -> Secret db_root_password existe déjà."
fi

if ! docker secret inspect db_password >/dev/null 2>&1; then
    DB_USER_PASS=$(openssl rand -base64 16 | tr -d '=+/')
    echo "$DB_USER_PASS" | docker secret create db_password -
    echo "  -> Secret db_password créé."
else
    echo "  -> Secret db_password existe déjà."
fi

# 2. Sauvegarde des credentials pour configuration GLPI
echo "[2/4] Sauvegarde des credentials..."
if [ -n "$DB_ROOT_PASS" ] && [ -n "$DB_USER_PASS" ]; then
    cat > /home/vagrant/.glpi_credentials << EOF
============================================
  Credentials MariaDB pour GLPI Setup
============================================
  Host     : mariadb
  Port     : 3306
  Database : glpi
  User     : glpi
  Password : $DB_USER_PASS

  Root Password : $DB_ROOT_PASS
============================================
  Utiliser ces credentials dans le wizard
  d'installation GLPI (étape base de données).
============================================
EOF
    chmod 600 /home/vagrant/.glpi_credentials
    echo "  -> Credentials sauvegardés dans ~/.glpi_credentials"
else
    echo "  -> Credentials déjà existants (secrets pré-existants)."
fi

# 3. Création des répertoires partagés (NFS)
echo "[3/4] Préparation des répertoires partagés..."
sudo mkdir -p /mnt/shared/glpi_data
sudo mkdir -p /mnt/shared/mysql_data
sudo mkdir -p /mnt/shared/certbot_conf
sudo mkdir -p /mnt/shared/certbot_www
sudo mkdir -p /mnt/shared/nginx_conf/conf.d
# www-data (uid 33) pour GLPI/Apache
sudo chown -R 33:33 /mnt/shared/glpi_data
# vagrant pour le reste
sudo chown -R vagrant:vagrant /mnt/shared/nginx_conf /mnt/shared/certbot_conf /mnt/shared/certbot_www
sudo chmod -R 777 /mnt/shared/glpi_data

echo "  Copie de la configuration Nginx..."
cp /home/vagrant/nginx/nginx.conf /mnt/shared/nginx_conf/nginx.conf
cp /home/vagrant/nginx/conf.d/* /mnt/shared/nginx_conf/conf.d/

# 4. Déploiement de la stack Docker
echo "[4/4] Déploiement de la stack Docker Swarm..."
cd /home/vagrant
docker stack deploy -c docker-stack.yml glpi_stack

echo ""
echo "========================================="
echo "  Stack déployée avec succès !"
echo "========================================="
echo ""
echo "Vérification des services :"
docker stack services glpi_stack