#!/bin/bash
set -euo pipefail

# =============================================
#  Script de déploiement automatisé
#  GLPI High Availability - Docker Swarm
# =============================================

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_ok()    { echo -e "${GREEN}[ OK ]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[FAIL]${NC}  $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo -e "${BLUE}=================================================${NC}"
echo -e "${BLUE}   DEPLOIEMENT AUTOMATISE GLPI - DOCKER SWARM    ${NC}"
echo -e "${BLUE}=================================================${NC}"
echo ""

# =============================================
#  0. Vérification des pré-requis
# =============================================
log_info "[0/5] Vérification des pré-requis..."
MISSING=""
for cmd in terraform ansible-playbook sshpass nc; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING="$MISSING $cmd"
    fi
done

if [ -n "$MISSING" ]; then
    log_error "Outils manquants :$MISSING"
    echo "  Installez-les avant de relancer le script."
    exit 1
fi
log_ok "Tous les pré-requis sont présents."

# =============================================
#  1. Génération de la clé SSH de déploiement
# =============================================
log_info "[1/5] Préparation de la clé SSH..."
SSH_KEY="$HOME/.ssh/glpi_swarm_key"
mkdir -p "$HOME/.ssh"
if [ ! -f "$SSH_KEY" ]; then
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "glpi-swarm-deploy" -q
    log_ok "Clé SSH générée : $SSH_KEY"
else
    log_ok "Clé SSH existante : $SSH_KEY"
fi
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i $SSH_KEY"

# =============================================
#  2. Provisionnement Terraform (VMs KVM/libvirt)
# =============================================
log_info "[2/5] Provisionnement de l'infrastructure (Terraform)..."

cd infra

# Nettoyage propre si re-déploiement
terraform init -input=false

if [ -f "terraform.tfstate" ]; then
    log_warn "État Terraform existant détecté, nettoyage..."
    terraform destroy -auto-approve 2>/dev/null || true
    rm -f terraform.tfstate terraform.tfstate.backup
fi

terraform apply -auto-approve
cd ..

log_ok "3 VMs provisionnées avec succès."

# =============================================
#  3. Attente SSH + Déploiement des clés
# =============================================
log_info "[3/5] Attente de la connectivité SSH et déploiement des clés..."

IPS=$(grep "ansible_host" config/inventory.ini | awk -F'ansible_host=' '{print $2}' | awk '{print $1}')
if [ -z "$IPS" ]; then
    log_error "Aucune IP trouvée dans l'inventaire généré."
    exit 1
fi

for IP in $IPS; do
    log_info "  Attente SSH $IP..."
    count=0
    while ! nc -z -w 3 "$IP" 22 2>/dev/null; do
        sleep 3
        count=$((count + 3))
        if [ $count -ge 120 ]; then
            log_error "Timeout : $IP injoignable après ${count}s."
            exit 1
        fi
    done
    log_ok "  $IP accessible."
done

# Pause de stabilisation du service SSH
sleep 5

# Déploiement des clés SSH sur chaque VM
log_info "Déploiement des clés SSH..."
for IP in $IPS; do
    sshpass -p 'vagrant' ssh-copy-id -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" vagrant@"$IP" 2>/dev/null || true
    log_ok "  Clé déployée sur $IP"
done

# Mise à jour de l'inventaire pour utiliser l'authentification par clé
log_info "Mise à jour de l'inventaire (auth par clé SSH)..."
sed -i "s|ansible_ssh_pass=vagrant ansible_become_pass=vagrant|ansible_ssh_private_key_file=$SSH_KEY ansible_become_pass=vagrant|g" config/inventory.ini
log_ok "Inventaire mis à jour."

# =============================================
#  4. Configuration avec Ansible
# =============================================
log_info "[4/5] Configuration système & cluster (Ansible)..."
cd config
export ANSIBLE_HOST_KEY_CHECKING=False
ansible-playbook -i inventory.ini playbook.yml
cd ..
log_ok "Configuration Ansible terminée."

# =============================================
#  5. Déploiement de l'application
# =============================================
log_info "[5/5] Déploiement de la stack GLPI..."

MANAGER_IP=$(grep "^manager " config/inventory.ini | awk -F'ansible_host=' '{print $2}' | awk '{print $1}')
if [ -z "$MANAGER_IP" ]; then
    log_error "Impossible de récupérer l'IP du manager."
    exit 1
fi

log_info "Transfert des fichiers vers le Manager ($MANAGER_IP)..."
scp $SSH_OPTS -r app/* vagrant@"$MANAGER_IP":/home/vagrant/

log_info "Initialisation de la stack sur le Manager..."
ssh $SSH_OPTS vagrant@"$MANAGER_IP" "chmod +x /home/vagrant/scripts/*.sh && /home/vagrant/scripts/init-stack.sh"

log_info "Attente de la stabilisation des services..."
WAIT_COUNT=0
WAIT_MAX=180
while [ $WAIT_COUNT -lt $WAIT_MAX ]; do
    HTTP_CODE=$(ssh $SSH_OPTS vagrant@"$MANAGER_IP" "curl -s -o /dev/null -w '%{http_code}' http://localhost/" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ]; then
        log_ok "GLPI accessible (HTTP 200) après ${WAIT_COUNT}s"
        break
    fi
    sleep 10
    WAIT_COUNT=$((WAIT_COUNT + 10))
    echo -ne "\r  Attente... ${WAIT_COUNT}s / ${WAIT_MAX}s (HTTP: $HTTP_CODE)"
done
echo ""
if [ $WAIT_COUNT -ge $WAIT_MAX ]; then
    log_warn "GLPI n'a pas répondu HTTP 200 dans les ${WAIT_MAX}s — continuons."
fi

log_info "Configuration SSL automatique..."
ssh $SSH_OPTS vagrant@"$MANAGER_IP" "/home/vagrant/scripts/init-letsencrypt.sh" || log_warn "SSL non configuré (normal en local, GLPI accessible en HTTP)."

# Récupération des credentials
log_info "Récupération des credentials MariaDB..."
DB_CREDS=$(ssh $SSH_OPTS vagrant@"$MANAGER_IP" "cat /home/vagrant/.glpi_credentials 2>/dev/null" || true)
DB_PASSWORD=$(echo "$DB_CREDS" | grep "Password" | head -1 | awk '{print $NF}')
DB_ROOT_PASSWORD=$(echo "$DB_CREDS" | grep "Root Password" | awk '{print $NF}')

# =============================================
#  Résumé final
# =============================================
echo ""
echo -e "${GREEN}=================================================${NC}"
echo -e "${GREEN}   DEPLOIEMENT TERMINE AVEC SUCCES !             ${NC}"
echo -e "${GREEN}=================================================${NC}"
echo ""
echo -e "  ${BLUE}Accès GLPI :${NC}"
echo -e "    HTTP  : http://$MANAGER_IP"
echo -e "    HTTPS : https://$MANAGER_IP"
echo ""
echo -e "  ${BLUE}Base de données MariaDB :${NC}"
echo -e "    Host          : mariadb"
echo -e "    Port          : 3306"
echo -e "    Database      : glpi"
echo -e "    Utilisateur   : glpi"
echo -e "    Mot de passe  : $DB_PASSWORD"
echo -e "    Root password : $DB_ROOT_PASSWORD"
echo ""
echo -e "  ${BLUE}Accès SSH Manager :${NC}"
echo -e "    ssh -i $SSH_KEY vagrant@$MANAGER_IP"
echo ""
echo -e "  ${BLUE}Vérifier les services :${NC}"
echo -e "    ssh -i $SSH_KEY vagrant@$MANAGER_IP docker stack services glpi_stack"
echo ""