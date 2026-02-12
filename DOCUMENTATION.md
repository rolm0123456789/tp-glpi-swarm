# Documentation Technique - Stack GLPI High Availability Swarm

**Participants :**
- VERGUET Romain
- DA SILVA Alexy
- ZIJP Quentin

---

## 1. Architecture

L'infrastructure repose sur un cluster **Docker Swarm** de 3 nœuds (1 Manager, 2 Workers), provisionnés via **Terraform** sur VirtualBox et configurés avec **Ansible**.

### Composants :
- **Frontend (Load Balancer)** : 3 instances Nginx en mode `global` (une par nœud).
- **Backend (Application)** : GLPI déployé en mode `replicated` (2 réplicas) pour la haute disponibilité.
- **Base de données** : MariaDB hébergée sur le nœud Manager (performance disque).
- **Stockage** : 
  - Système de fichiers partagé **NFS** hébergé sur le Manager et monté sur `/mnt/shared` sur tous les nœuds.
  - Permet le partage des configurations Nginx, des certificats SSL et des données GLPI entre tous les nœuds du Swarm.

### Flux Réseau :
1. L'utilisateur accède via HTTPS (port 443).
2. Nginx (sur n'importe quel nœud) termine le SSL et proxy vers le service GLPI interne.
   - Si le domaine est public, **Let's Encrypt** génère un certificat valide.
   - Si le domaine est local (`glpi.local`), un **certificat auto-signé** est généré automatiquement.
3. GLPI communique avec MariaDB via un réseau overlay chiffré (`internal: true`).

## 2. Sécurité

### Système (Ansible)
- **Firewall (UFW)** : Configuration stricte autorisant uniquement les ports nécessaires :
  - SSH (22)
  - HTTP/HTTPS (80, 443)
  - Docker Swarm (2377, 7946, 4789)
- **SSH Hardening** :
  - Désactivation de l'authentification par mot de passe.
  - Désactivation du login root.

### Application (Docker)
- **Secrets Management** : Les mots de passe (DB Root, DB User) sont **générés aléatoirement** lors du premier déploiement et stockés via **Docker Secrets**.
- **Réseaux Isolés** : La base de données est isolée dans un réseau `backend` interne, inaccessible depuis l'extérieur. Seul GLPI peut y accéder.
- **SSL/TLS** : Implémentation de Let's Encrypt via Certbot. Script d'automatisation inclus pour la génération et le renouvellement.

## 3. Déploiement Automatisé

Le script `./deploy.sh` orchestre l'ensemble du déploiement :
1. **Terraform** provisionne les 3 VMs.
2. **Ansible** configure les serveurs, installe Docker, configure le NFS et sécurise les nœuds.
3. **Docker Stack** déploie les services.
4. **Script SSL** (`init-letsencrypt.sh`) génère les certificats et active la configuration HTTPS sur Nginx.

### Utilisation

```bash
./deploy.sh
```

---
*Projet réalisé dans le cadre du cours d'Architecture Logicielle - ESGI.*
