# Documentation Technique - Stack GLPI High Availability Swarm

**Participants :**
- VERGUET Romain
- DA SILVA Alexy
- ZIJP Quentin

---

## 1. Architecture Générale

L'infrastructure repose sur un cluster **Docker Swarm** de 3 nœuds (1 Manager, 2 Workers), provisionnés automatiquement via **Terraform + Vagrant** (VirtualBox) et configurés avec **Ansible**.

Chaque VM utilise l'image **bento/ubuntu-22.04** (2 vCPU, 2 Go RAM) avec des IPs statiques sur le réseau host-only `192.168.56.0/24`.

### Schéma des composants

```
                    ┌──────────────────────────────────────────────┐
                    │              UTILISATEUR                     │
                    └───────────────┬──────────────────────────────┘
                                    │ HTTP/HTTPS (80/443)
                    ┌───────────────▼──────────────────────────────┐
                    │          DOCKER SWARM CLUSTER                │
                    │                                              │
                    │  ┌────────┐  ┌────────┐  ┌────────┐         │
                    │  │ Nginx  │  │ Nginx  │  │ Nginx  │  Global │
                    │  │ Node 1 │  │ Node 2 │  │ Node 3 │  (x3)   │
                    │  └───┬────┘  └───┬────┘  └───┬────┘         │
                    │      │           │           │               │
                    │      └───────────┼───────────┘               │
                    │                  │ Réseau overlay: frontend   │
                    │          ┌───────▼────────┐                  │
                    │          │   GLPI (PHP)   │                  │
                    │          │   + Certbot    │                  │
                    │          └───────┬────────┘                  │
                    │                  │ Réseau overlay: backend   │
                    │          ┌───────▼────────┐    (internal)    │
                    │          │   MariaDB      │                  │
                    │          │   10.11        │                  │
                    │          └────────────────┘                  │
                    │                                              │
                    │  Stockage: NFS (/mnt/shared) sur le Manager │
                    └──────────────────────────────────────────────┘
```

### Composants déployés

| Service   | Image                  | Mode     | Réplicas | Réseau(x)          |
|-----------|------------------------|----------|----------|--------------------|
| Nginx     | `nginx:1.25-alpine`    | Global   | 3 (1/nœud) | frontend         |
| Certbot   | `certbot/certbot`      | Répliqué | 1        | —                  |
| GLPI      | `diouxx/glpi`          | Répliqué | 1        | frontend + backend |
| MariaDB   | `mariadb:10.11`        | Répliqué | 1        | backend (internal) |

### Flux réseau

1. L'utilisateur accède via HTTP (80) ou HTTPS (443).
2. Nginx (sur n'importe quel nœud via Swarm) termine le SSL et proxy vers le service GLPI.
   - Si le domaine est public → certificat **Let's Encrypt** valide.
   - Si le domaine est local (`glpi.local`) → **certificat auto-signé** généré automatiquement.
3. GLPI communique avec MariaDB via un réseau overlay interne (`internal: true`) — inaccessible depuis l'extérieur.

---

## 2. Sécurité

### 2.1 Système (Ansible)

- **Pare-feu UFW** : Politique deny par défaut. Seuls les ports suivants sont autorisés :

  | Port  | Proto | Usage                      |
  |-------|-------|----------------------------|
  | 22    | TCP   | SSH                        |
  | 80    | TCP   | HTTP                       |
  | 443   | TCP   | HTTPS                      |
  | 2377  | TCP   | Docker Swarm Management    |
  | 4789  | UDP   | Docker Overlay Network     |
  | 7946  | TCP/UDP | Docker Node Discovery    |
  | 2049  | TCP   | NFS (192.168.56.0/24 uniquement) |

- **SSH Hardening** :
  - Authentification par **clé SSH Ed25519** uniquement (mot de passe désactivé).
  - Login root désactivé (`PermitRootLogin no`).
  - Clé SSH générée automatiquement et déployée par le script `deploy.sh`.

- **Optimisation noyau** :
  - `vm.swappiness = 10` (réduction de l'utilisation du swap).
  - `fs.file-max = 65535` (augmentation du nombre max de fichiers ouverts).

### 2.2 Application (Docker)

- **Docker Secrets** : Les mots de passe MariaDB (root et user) sont **générés aléatoirement** au premier déploiement et stockés via Docker Secrets. Ils ne sont jamais en clair dans les fichiers de configuration.
- **Réseaux isolés** :
  - `frontend` (overlay) : Nginx ↔ GLPI.
  - `backend` (overlay, **internal**) : GLPI ↔ MariaDB. Aucun accès externe possible.
- **Volume local pour MariaDB** : Volume nommé Docker (pas NFS) pour la performance et l'intégrité des données.
- **NFS restreint** : Exports limités au réseau `192.168.56.0/24`.
- **Version Nginx masquée** : `server_tokens off`.

### 2.3 SSL/TLS

- **Let's Encrypt** via Certbot (tentative automatique).
- Fallback auto-signé pour les domaines locaux.
- Protocoles : **TLSv1.2 + TLSv1.3** uniquement.
- Headers de sécurité HTTPS :
  - `Strict-Transport-Security` (HSTS)
  - `X-Frame-Options: SAMEORIGIN`
  - `X-Content-Type-Options: nosniff`
  - `X-XSS-Protection`
  - `Referrer-Policy`

---

## 3. Performance

### Nginx
- `worker_processes auto` : Ajustement automatique au nombre de CPUs.
- `worker_connections 2048` : Capacité de connexions simultanées.
- Compression **gzip** activée (CSS, JS, JSON, XML).
- `sendfile`, `tcp_nopush`, `tcp_nodelay` activés.
- `client_max_body_size 20M` pour les uploads GLPI.

### MariaDB
- `innodb-buffer-pool-size=256M` : Cache InnoDB optimisé pour 2Go de RAM.
- `innodb-flush-log-at-trx-commit=2` : Écriture asynchrone pour la performance (compromis acceptable en VM).
- `max-connections=200` : Capacité de connexions simultanées.
- `character-set-server=utf8mb4` : Encodage complet Unicode.
- Volume local (`mariadb_data`) au lieu de NFS pour éviter la latence réseau sur les I/O base.

### Docker Swarm
- **Limites de ressources** définies pour chaque service (CPU, mémoire) — évite la surconsommation.
- **Healthchecks** sur tous les services pour le self-healing automatique.
- Mode `global` pour Nginx : un conteneur par nœud, zéro contention réseau.

---

## 4. Déploiement Automatisé

Le script `./deploy.sh` orchestre l'ensemble du déploiement en **5 étapes** :

```
Étape 0 → Vérification des pré-requis (terraform, ansible-playbook, vagrant, VBoxManage, sshpass)
Étape 1 → Génération de la clé SSH Ed25519
Étape 2 → Provisionnement des 3 VMs (Terraform + Vagrant)
Étape 3 → Attente SSH + déploiement des clés + mise à jour de l'inventaire
Étape 4 → Ansible : Installation Docker, NFS, UFW, Swarm, SSH hardening
Étape 5 → Déploiement Docker Stack + attente GLPI + configuration SSL
```

### Pré-requis sur la machine hôte

- Terraform >= 0.13
- Vagrant >= 2.3
- Ansible >= 2.9
- VirtualBox >= 6.0
- `sshpass`

### Lancement

```bash
chmod +x deploy.sh
./deploy.sh
```

Le script affiche à la fin :
- L'URL d'accès à GLPI (HTTP et HTTPS).
- Les credentials MariaDB pour le wizard d'installation GLPI.
- La commande SSH pour accéder au Manager.

---

## 5. Arborescence du Projet

```
tp-glpi-swarm/
├── deploy.sh                    # Script maître de déploiement (entrée unique)
├── .gitignore                   # Fichiers ignorés par Git
├── DOCUMENTATION.md             # Ce document
├── README.md                    # Guide rapide
├── tp                           # Sujet du TP
│
├── app/                         # Configuration applicative
│   ├── docker-stack.yml         # Définition de la stack Docker Swarm
│   ├── nginx/
│   │   ├── nginx.conf           # Configuration principale Nginx
│   │   └── conf.d/
│   │       └── glpi.conf        # Vhost GLPI (HTTP + HTTPS)
│   └── scripts/
│       ├── init-stack.sh        # Initialisation stack (secrets, NFS, deploy)
│       └── init-letsencrypt.sh  # Génération certificats SSL
│
├── config/                      # Configuration Ansible
│   ├── ansible.cfg              # Paramètres Ansible
│   ├── inventory.ini            # Inventaire (généré automatiquement par Terraform)
│   └── playbook.yml             # Playbook de configuration (5 plays)
│
└── infra/                       # Infrastructure as Code
    ├── main.tf                  # Définition Terraform (null_resource + Vagrant)
    ├── Vagrantfile              # Définition des 3 VMs VirtualBox
    ├── variables.tf             # Variables Terraform
    ├── versions.tf              # Versions des providers (null, local)
    └── templates/
        └── inventory.tpl        # Template d'inventaire Ansible
```

---

*Projet réalisé dans le cadre du cours d'Architecture Logicielle - ESGI.*
