#!/bin/bash
set -euo pipefail

# =============================================
#  Script de déploiement automatisé
#  GLPI High Availability - Docker Swarm
#  Orchestrateur minimal : SSH → Terraform → Ansible
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
#  1. Vérification des pré-requis
# =============================================
log_info "[1/3] Vérification des pré-requis..."
MISSING=""
for cmd in terraform ansible-playbook; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING="$MISSING $cmd"
    fi
done
if [ -n "$MISSING" ]; then
    log_error "Outils manquants :$MISSING"
    exit 1
fi

SSH_KEY="$HOME/.ssh/glpi_swarm_key"
mkdir -p "$HOME/.ssh"
if [ ! -f "$SSH_KEY" ]; then
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "glpi-swarm-deploy" -q
    log_ok "Clé SSH générée : $SSH_KEY"
else
    log_ok "Clé SSH existante : $SSH_KEY"
fi

# =============================================
#  2. Provisionnement Terraform (VMs KVM/libvirt)
# =============================================
log_info "[2/3] Provisionnement de l'infrastructure (Terraform)..."
cd infra
terraform init -input=false

if [ -f "terraform.tfstate" ]; then
    log_warn "État Terraform existant détecté, nettoyage..."
    terraform destroy -auto-approve 2>/dev/null || true
    rm -f terraform.tfstate terraform.tfstate.backup
fi

terraform apply -auto-approve \
    -var "ssh_public_key=$(cat "$SSH_KEY.pub")" \
    -var "ssh_private_key_path=$SSH_KEY"
cd ..
log_ok "3 VMs provisionnées avec succès."

# =============================================
#  3. Configuration et déploiement (Ansible)
# =============================================
log_info "[3/3] Configuration système, cluster et application (Ansible)..."
cd config
export ANSIBLE_HOST_KEY_CHECKING=False
ansible-playbook -i inventory.ini playbook.yml
cd ..
log_ok "Déploiement Ansible terminé."

# =============================================
#  Résumé final
# =============================================
MANAGER_IP=$(grep "ansible_host" config/inventory.ini | head -1 | awk -F'ansible_host=' '{print $2}' | awk '{print $1}')
DB_PASSWORD=""
DB_ROOT_PASSWORD=""
if [ -f ".glpi_credentials" ]; then
    DB_PASSWORD=$(grep "Password" .glpi_credentials | head -1 | awk '{print $NF}')
    DB_ROOT_PASSWORD=$(grep "Root Password" .glpi_credentials | awk '{print $NF}')
fi

echo ""
echo -e "${GREEN}=================================================${NC}"
echo -e "${GREEN}   DEPLOIEMENT TERMINE AVEC SUCCES !             ${NC}"
echo -e "${GREEN}=================================================${NC}"
echo ""
echo -e "  ${BLUE}Accès GLPI :${NC}"
echo -e "    HTTP  : http://$MANAGER_IP"
echo -e "    HTTPS : https://$MANAGER_IP"
echo ""
echo -e "  ${BLUE}Identifiants GLPI par défaut :${NC}"
echo -e "    glpi / glpi  (Super-Admin)"
echo ""
echo -e "  ${BLUE}Base de données MariaDB :${NC}"
echo -e "    Utilisateur   : glpi"
echo -e "    Mot de passe  : $DB_PASSWORD"
echo -e "    Root password : $DB_ROOT_PASSWORD"
echo ""
echo -e "  ${BLUE}Accès SSH Manager :${NC}"
echo -e "    ssh -i $SSH_KEY vagrant@$MANAGER_IP"
echo ""