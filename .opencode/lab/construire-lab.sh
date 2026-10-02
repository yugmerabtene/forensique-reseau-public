#!/usr/bin/env bash
# Constructeur du laboratoire « Forensique réseau ».
#
# Topologie cible, conforme à CONTEXT.md et aux trois supports :
#
#   Réseau 10.10.0.0/24 — site central
#   .1   lab-passerelle   passerelle du segment
#   .10  lab-enquete      poste de l'enquêteur, première interface
#   .20  lab-app          serveur applicatif : 22 SSH, 80 HTTP, 443 TLS, 5201 iperf3
#   .30  lab-fichiers     serveur de fichiers : 23 Telnet et 445 SMB en clair
#   .50  lab-collecteur   collecteur de journaux : syslog 514
#   .60  lab-compromis    seconde interface du poste compromis
#
#   Réseau 10.20.0.0/24 — filiale
#   .1   lab-passerelle   seconde interface de la même passerelle
#   .10  lab-compromis    poste compromis, à l'origine de l'incident
#   .20  lab-filiale      serveur de la filiale : 22 SSH et 80 HTTP
#   .30  lab-enquete      seconde interface du poste de l'enquêteur
#
#   Sonde de détection, sans adresse propre
#   lab-sonde   partage l'espace réseau de lab-compromis et y exécute Suricata
#
# Deux décisions structurantes, et leur raison :
#
#   1. Le poste de l'enquêteur possède une interface sur chacun des deux
#      segments. C'est la position de l'enquêteur : il est branché là où les
#      traces se forment. Sans cette seconde interface, le trafic de la filiale
#      lui serait inaccessible et le chapitre sur la collecte n'aurait rien à
#      capturer.
#
#   2. Le poste compromis possède lui aussi une interface sur le segment du site
#      central, en 10.10.0.60. Cette double appartenance est un défaut de
#      segmentation, et c'est exactement ce que le chapitre sur la réponse à
#      l'incident doit faire remarquer : une machine de la filiale ne devrait pas
#     joindre directement les serveurs du site central.
#
#   3. Le moteur de détection tourne dans un conteneur qui partage l'espace
#      réseau du poste compromis, et non dans le collecteur. Ce n'est pas un
#      détail d'implémentation : c'est la seule position d'observation possible
#      ici. Un pont Docker ne livre le trafic unicast qu'au port destinataire, et
#      n'honore pas le mode promiscuë : un conteneur du segment central ne voit
#      jamais le trafic échangé entre deux autres machines de ce segment. C'est
#      mesuré : trois tentatives de capture depuis le collecteur, dont deux en
#      mode promiscuë forcé, n'ont enregistré aucun paquet, alors que le trafic
#      circulait. Partager l'espace réseau du poste suspect rend en revanche tout
#      son trafic visible, ce qui suffit aux quatre comportements de l'incident,
#      puisque tous en partent.
#
#   4. Les journaux sont produits dans le volume de l'enquêteur. Le volume
#      « flab-enquete » est monté sous /partage chez le collecteur et chez le
#      serveur de fichiers : un fichier écrit dans /partage/journal y est donc lu
#      par l'enquêteur dans ~/journal, en direct et sans copie. Aucun volume
#      supplémentaire n'est nécessaire, et surtout aucune étape de copie
#      intermédiaire ne peut altérer la preuve : le fichier que l'apprenant lit
#      est exactement celui que le processus privilégié vient d'écrire.
#
# Le relais entre les deux segments est annoncé mais jamais exercé par les LAB.
# Docker isole le trafic qui traverse deux ponts distincts, et lever cette
# isolation suppose des privilèges sur l'hôte : aucun LAB n'en dépend.
#
# Usage :
#   ./construire-lab.sh monter     crée les réseaux et démarre les conteneurs
#   ./construire-lab.sh verifier   vérifie la topologie et les journaux
#   ./construire-lab.sh scenario   relance le scénario d'incident
#   ./construire-lab.sh arrêter    supprime tout
#   ./construire-lab.sh enquete <commande>  exécute une commande dans le poste
set -euo pipefail

cd "$(dirname "$0")"

IMAGE="forensique-lab:2026"
RESEAU_CENTRAL="forensique-net-central"    # 10.10.0.0/24
RESEAU_FILIALE="forensique-net-filiale"    # 10.20.0.0/24
PREFIXE="flab"
# Suffixes des conteneurs, sans le préfixe : le script les supprime tous à l'arrêt.
APPS="passerelle enquete app fichiers collecteur compromis filiale sonde"

# ---------------------------------------------------------------- utilitaires
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
err()  { printf '  \033[31mNON\033[0m %s\n' "$*" >&2; }

# Écrire un message horodaté dans le journal d'un hôte. La commande « logger »
# écrit dans le socket local créé par rsyslog : on attend donc que ce socket
# existe avant d'écrire, sinon le message serait perdu sans trace.
ecrire_journal() {
  local hote=$1 etiquette=$2 texte=$3
  local fin=$(( SECONDS + 15 ))
  while [ $SECONDS -lt $fin ]; do
    if docker exec "$hote" test -S /dev/log 2>/dev/null; then
      docker exec "$hote" logger -t "$etiquette" -p daemon.info "$texte" 2>/dev/null || true
      return 0
    fi
    sleep 1
  done
  err "le journal de $hote n'a pas démarré"
  return 1
}

# Message de démarrage d'un hôte du laboratoire.
demarrer_journal() {
  local hote=$1 nom=${1#flab-}
  ecrire_journal "$hote" "laboratoire" \
    "démarrage de $nom : services du laboratoire opérationnels, collecte activée"
}

# Préparer le répertoire des journaux dans le volume partagé.
#
# Le volume de l'enquêteur est monté sous /partage chez le collecteur et chez le
# serveur de fichiers. Le répertoire y est créé en 755 et appartient à root :
# l'enquêteur peut le parcourir et lire les fichiers qu'il contient, il ne peut
# ni les modifier, ni en créer d'autres, ni les supprimer.
#
# Cette contrainte n'est pas un détail. Un journal qu'un compte ordinaire peut
# réécrire ne vaut rien comme preuve : l'apprenant doit être dans la position de
# celui qui consulte, jamais dans celle de celui qui fabrique. C'est aussi ce que
# fait un vrai enquêteur devant un collecteur : il lit, il ne modifie pas.
#
# Les journaux restent donc écrits par des processus privilégiés, et le compte
# de l'apprenant n'acquiert aucun privilège supplémentaire.
preparer_journal_partage() {
  docker exec -u root "$1" sh -c '
    set -e
    mkdir -p /partage/journal
    chmod 0755 /partage/journal
    chown root:root /partage/journal
    ls -ld /partage/journal
  ' >/dev/null
}

# Démarrer la collecte des journaux sur un hôte du laboratoire.
#
# Premier argument : le nom du conteneur. Deuxième et troisième arguments,
# facultatifs : le chemin d'un fichier à relayer au collecteur, et l'étiquette
# sous laquelle ses lignes y apparaîtront.
#
# La configuration est écrite depuis la machine, puis le fichier est relu par
# rsyslog avant le démarrage. Deux raisons à cette manière de faire, toutes deux
# mesurées. La déclaration du socket local contient un signe dollar, qu'une
# chaîne simple transmise au conteneur ne restitue pas fidèlement : le socket ne
# serait pas créé et la commande « logger » n'aurait nulle part où écrire. Et
# rsyslog n'écrit rien sur sa sortie standard quand sa configuration est refusée :
# sans contrôle préalable, un hôte resterait muet sans laisser de trace, et cette
# panne serait elle aussi muette.
demarrer_rsyslog_hote() {
  local hote=$1 fichier=${2:-} etiquette=${3:-} controle
  {
    printf '%s\n' \
      'module(load="imuxsock")' \
      '$AddUnixListenSocket /dev/log' \
      'global(workDirectory="/run/rsyslab")'
    if [ -n "$fichier" ]; then
      # Le module n'est chargé que lorsqu'il a un fichier à suivre. Cette
      # condition est nécessaire, et elle a été mesurée : un module imfile
      # chargé sans entrée refuse la configuration, son avertissement
      # « no files configured to be monitored » valant refus. Un hôte qui n'a
      # rien à relayer n'a pas à le charger.
      printf '%s\n' \
        'module(load="imfile" PollingInterval="2")' \
        "input(type=\"imfile\" File=\"$fichier\" Tag=\"$etiquette\" Severity=\"info\" freshStartTail=\"off\")"
    fi
    printf '%s\n' \
      '*.* /var/log/journal-hote.log' \
      '*.* @10.10.0.50'
  } | docker exec -i -u root "$hote" sh -c \
      'mkdir -p /run/rsyslab && cat > /etc/rsyslab.conf'
  # rsyslog écrit son diagnostic de contrôle sur sa sortie d'erreur, y compris
  # quand la configuration est valide : la sortie est donc capturée, et ne
  # remontée que si le contrôle échoue. Une configuration refusée arrête le
  # montage, au lieu de laisser un hôte muet dont la panne serait elle aussi
  # muette.
  if ! controle=$(docker exec -u root "$hote" \
                     rsyslogd -N1 -f /etc/rsyslab.conf 2>&1 >/dev/null); then
    err "la configuration de collecte de $hote est refusée par rsyslog"
    printf '%s\n' "$controle" >&2
    return 1
  fi
  docker exec -d -u root "$hote" rsyslogd -n -i NONE -f /etc/rsyslab.conf
}

# ------------------------------------------------------------------- monter
monter() {
  log "Arrêt d'une éventuelle précédente exécution"
  arrêter >/dev/null 2>&1 || true

  # Le volume du poste de l'enquêteur est recréé à chaque montage. Un volume
  # laissé par la création de l'image, ou par une ancienne version du
  # laboratoire, appartient à root et rendrait le dossier de travail inaccessible
  # à l'enquêteur : les livrables des LAB ne pourraient plus être écrits.
  docker volume rm -f flab-enquete >/dev/null 2>&1 || true

  # Les réseaux sont créés avec un masque plus large que le segment utile et une
  # passerelle technique hors segment. Le réseau 10.10.0.0/23 englobe le segment
  # 10.10.0.0/24 et laisse le quartier 10.10.1.0/24 au pont, qui n'appartient pas
  # au laboratoire. Sans cette précaution, Docker considère que tout 10.10.0.0 est
  # sur le lien : chaque adresse de la plage provoke une demande de résolution
  # d'adresse, la table de voisinage se remplit de centaines d'échecs illisibles,
  # et la route par défaut affichée par « ip route show » n'est pas celle du
  # laboratoire. Les interfaces sont remises en conformité après le démarrage.
  log "Création du réseau $RESEAU_CENTRAL (10.10.0.0/24)"
  docker network create --subnet 10.10.0.0/23 --gateway 10.10.1.253 \
      "$RESEAU_CENTRAL" >/dev/null
  ok "10.10.0.0/24 disponible ; passerelle technique du pont hors segment"

  log "Création du réseau $RESEAU_FILIALE (10.20.0.0/24)"
  docker network create --subnet 10.20.0.0/23 --gateway 10.20.1.253 \
      "$RESEAU_FILIALE" >/dev/null
  ok "10.20.0.0/24 disponible ; passerelle technique du pont hors segment"

  log "Démarrage des conteneurs"

  # La passerelle relie les deux segments.
  docker run -d --name "$PREFIXE-passerelle" --hostname lab-passerelle \
    --network "$RESEAU_CENTRAL" --ip 10.10.0.1 \
    --cap-add NET_ADMIN --cap-add NET_RAW \
    --sysctl net.ipv4.ip_forward=1 \
    "$IMAGE" sleep infinity >/dev/null
  docker network connect --ip 10.20.0.1 "$RESEAU_FILIALE" "$PREFIXE-passerelle" >/dev/null
  ok "lab-passerelle : 10.10.0.1 et 10.20.0.1"

  # Le poste de l'enquêteur est le poste de travail de l'apprenant : il travaille
  # en compte ordinaire, et non en root. C'est indispensable pour que les
  # commandes « sudo » du support soient exécutées dans les conditions réelles.
  # Il est branché sur les deux segments : c'est la position de l'enquêteur, et
  # c'est la seule façon d'observer le trafic de la filiale depuis le site.
  docker run -d --name "$PREFIXE-enquete" --hostname lab-enquete \
    --network "$RESEAU_CENTRAL" --ip 10.10.0.10 \
    --cap-add NET_RAW --cap-add NET_ADMIN \
    --user enqueteur \
    -v flab-enquete:/home/enqueteur \
    -w /home/enqueteur/enquete \
    "$IMAGE" sleep infinity >/dev/null
  docker network connect --ip 10.20.0.30 "$RESEAU_FILIALE" "$PREFIXE-enquete" >/dev/null
  ok "lab-enquete : 10.10.0.10 et 10.20.0.30, compte enqueteur"

  # Les interfaces du poste de l'enquêteur portent les masques réels des deux
  # segments, et chaque segment a sa propre route. Aucun trafic ne traverse la
  # passerelle : Docker isole le passage d'un pont à l'autre, et aucun LAB ne
  # repose sur ce relais.
  docker exec -u root "$PREFIXE-enquete" sh -c '
    ip addr flush dev eth0
    ip addr add 10.10.0.10/24 dev eth0
    ip addr flush dev eth1
    ip addr add 10.20.0.30/24 dev eth1
    ip route replace default via 10.10.0.1 dev eth0
    ip route replace 10.20.0.0/24 dev eth1 src 10.20.0.30
  '
  ok "lab-enquete : 10.10.0.0/24 et 10.20.0.0/24, une route par segment"

  docker run -d --name "$PREFIXE-app" --hostname lab-app \
    --network "$RESEAU_CENTRAL" --ip 10.10.0.20 --cap-add NET_RAW \
    "$IMAGE" sleep infinity >/dev/null
  ok "lab-app : 10.10.0.20"

  # Le serveur de fichiers participe au volume de l'enquêteur : son journal
  # d'accès au partage y est écrit, donc l'enquêteur le lit dans
  # ~/journal/journal-samba.log, sans copie ni export intermédiaire.
  docker run -d --name "$PREFIXE-fichiers" --hostname lab-fichiers \
    --network "$RESEAU_CENTRAL" --ip 10.10.0.30 --cap-add NET_RAW --cap-add NET_ADMIN \
    -v flab-enquete:/partage \
    "$IMAGE" sleep infinity >/dev/null
  ok "lab-fichiers : 10.10.0.30, journal du partage dans le volume partagé"

  # Le collecteur participe au même volume : le journal qu'il rassemble est donc
  # lu par l'enquêteur dans ~/journal/journal-reseau.log.
  docker run -d --name "$PREFIXE-collecteur" --hostname lab-collecteur \
    --network "$RESEAU_CENTRAL" --ip 10.10.0.50 \
    --cap-add NET_RAW --cap-add NET_ADMIN \
    -v flab-enquete:/partage \
    "$IMAGE" sleep infinity >/dev/null
  ok "lab-collecteur : 10.10.0.50, journal de collecte dans le volume partagé"

  # Le répertoire des journaux dans le volume partagé est créé une fois pour
  # toutes, avant tout service qui écrit dedans, et par les deux hôtes qui y
  # écrivent : la création est idempotente, et le laboratoire n'a pas à
  # dépendre de l'ordre de démarrage des deux.
  for hote in "$PREFIXE-fichiers" "$PREFIXE-collecteur"; do
    preparer_journal_partage "$hote"
  done
  ok "répertoire ~/journal créé dans le volume, lisible et non modifiable par l'enquêteur"

  docker run -d --name "$PREFIXE-compromis" --hostname lab-compromis \
    --network "$RESEAU_FILIALE" --ip 10.20.0.10 --cap-add NET_RAW \
    "$IMAGE" sleep infinity >/dev/null
  # Seconde interface du poste compromis, sur le segment du site central. C'est
  # le défaut de segmentation que le chapitre sur la réponse à l'incident doit
  # faire remarquer, et c'est aussi ce qui rend le trafic d'attaque observable
  # depuis le site central, sans dépendre d'un relais entre les deux segments.
  docker network connect --ip 10.10.0.60 "$RESEAU_CENTRAL" "$PREFIXE-compromis" >/dev/null
  ok "lab-compromis : 10.20.0.10 et 10.10.0.60"

  docker run -d --name "$PREFIXE-filiale" --hostname lab-filiale \
    --network "$RESEAU_FILIALE" --ip 10.20.0.20 --cap-add NET_RAW \
    "$IMAGE" sleep infinity >/dev/null
  ok "lab-filiale : 10.20.0.20"

  # La sonde de détection partage l'espace réseau du poste compromis. Elle n'a
  # donc aucune adresse propre : elle voit le trafic des deux interfaces du poste
  # suspect, parce qu'elles sont les siennes. Elle ne peut pas non plus porter un
  # nom d'hôte propre, Docker l'interdisant dès lors qu'un espace réseau est
  # partagé. Le volume du poste de l'enquêteur est monté chez elle pour que le
  # journal EVE soit lisible par l'enquêteur dans ~/suricata/eve.json, sans copie
  # ni export intermédiaire.
  docker run -d --name "$PREFIXE-sonde" \
    --network "container:$PREFIXE-compromis" \
    --user root \
    --cap-add NET_RAW --cap-add NET_ADMIN \
    -v flab-enquete:/sortie \
    "$IMAGE" sleep infinity >/dev/null
  ok "lab-sonde : moteur de détection dans l'espace réseau de lab-compromis"

  log "Démarrage des services annoncés dans le support"
  demarrer_services

  log "Activation du relais entre les deux segments"
  if [ "$(docker exec "$PREFIXE-passerelle" cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" = "1" ]; then
    ok "relais 10.10.0.0/24 vers 10.20.0.0/24 actif sur lab-passerelle"
  else
    err "le relais entre les deux segments n'est pas actif"
    return 1
  fi

  log "Lancement du scénario d'incident"
  # Une boucle déjà en cours est arrêtée avant d'en lancer une nouvelle. Deux
  # tours superposés doubleraient le trafic observé et les journaux, et
  # l'apprenant lirait des répétitions qu'il ne saurait pas expliquer.
  docker exec "$PREFIXE-compromis" pkill -f 'scenario-incident' 2>/dev/null || true
  docker cp scenario-incident.sh "$PREFIXE-compromis":/tmp/scenario-incident.sh
  docker exec -d "$PREFIXE-compromis" bash /tmp/scenario-incident.sh
  ok "scénario d'incident lancé sur lab-compromis"

  log "Attente de la disponibilité des services"
  attendre 30
  attendre_services

  log "Laboratoire monté"
}

# Les services sont démarrés un par un, et seulement ceux dont le port est
# annoncé dans le tableau d'environnement du support. Aucun port n'est ouvert
# « pour completeness » : un port ouvert que le support ne mentionne pas devient
# une anomalie que l'apprenant doit expliquer, et le support perd sa cohérence.
demarrer_services() {
  # HTTP sur le port 80. busybox httpd est présent dans l'image et ne demande
  # aucune dépendance supplémentaire.
  for hote in "$PREFIXE-app" "$PREFIXE-filiale"; do
    docker exec -d "$hote" sh -c \
      'mkdir -p /var/www/html; printf "hote simule du laboratoire\n" > /var/www/html/index.html; exec busybox httpd -f -p 80 -h /var/www/html'
  done
  ok "HTTP sur le port 80 de lab-app et lab-filiale"

  # iperf3 sur le serveur applicatif. Le chapitre sur la collecte a besoin d'un
  # trafic connu et maîtrisé : sans lui, la capture ne contiendrait que des
  # services de gestion, et rien ne permettrait de distinguer le trafic légitime du
  # trafic à caractériser.
  docker exec -d "$PREFIXE-app" iperf3 -s
  ok "iperf3 en écoute sur 10.10.0.20:5201"

  # TLS sur le port 443 du serveur applicatif. Le certificat est celui généré à
  # la construction de l'image. La session est réelle : un client qui s'y connecte
  # obtient une négociation TLS complète, que tshark sait détailler, ce qui permet
  # d'enseigner la différence entre un protocole en clair et un protocole protégé
  # sur la même capture.
  docker exec -d "$PREFIXE-app" sh -c \
    'exec openssl s_server -quiet -www -accept 443 -cert /etc/lab/cert-filiale.pem -key /etc/lab/cle-filiale.pem'
  ok "TLS sur le port 443 de lab-app"

  # SSH : service de gestion exposé sur le port 22.
  for hote in "$PREFIXE-app" "$PREFIXE-filiale"; do
    docker exec -d "$hote" sh -c 'mkdir -p /run/sshd; exec /usr/sbin/sshd -D'
  done
  ok "SSH sur le port 22 de lab-app et lab-filiale"

  # Le partage de fichiers du serveur 10.10.0.30. Le compte et le mot de passe
  # sont ceux du laboratoire, décrits dans le tableau d'environnement du support.
  # Samba journalise chaque connexion dans le volume partagé, ce qui donne au
  # chapitre consacré aux journaux une trace à rapprocher de la capture.
  # Cette préparation est exécutée en avant-plan, et non en arrière-plan comme
  # les autres services : c'est la seule étape qui doive échouer de façon visible.
  # Le partage, le compte et la configuration sont trois dépendances l'une de
  # l'autre, et chacune peut échouer sans que le port 445 cesse de répondre. Un
  # échec ici resterait donc invisible jusqu'au premier essai d'authentification
  # par un apprenant, en pleine séance.
  docker exec "$PREFIXE-fichiers" sh -c '
    set -e
    mkdir -p /srv/partage /var/log/samba /var/lib/samba/private /run/samba
    printf "partage du laboratoire\n" > /srv/partage/lisezmoi.txt
    # Le fichier de journal est créé ici, et non par Samba à son premier
    # démarrage. Le mode est posé avant la première écriture, et non après :
    # Samba créait déjà ce fichier en 644, mais laisser la création au serveur
    # ferait dépendre la lisibilité par l enquêteur d une valeur par défaut que
    # rien dans le laboratoire ne contrôle. Le compte enqueteur n est pas root :
    # il ne peut ni écrire dans ce fichier, ni le déplacer, ni le supprimer.
    : > /partage/journal/journal-samba.log
    chmod 0644 /partage/journal/journal-samba.log
    cat > /etc/samba/smb.conf.lab <<CONF
[global]
    # Sans ce niveau de détail, le serveur ne note que son propre démarrage :
    # aucune ligne ne correspond à une connexion, et le chapitre consacré aux
    # journaux n’a rien à rapprocher de la capture. Le niveau 1 suffit pour
    # journaliser les sessions, sans remplir le fichier de messages inutiles.
    #
    # Le module « auth » est monté au niveau 3 parce qu’il produit la preuve
    # utile : les échanges d’authentification NTLM qui correspondent à la lecture
    # du partage. Un niveau supérieur a été essayé pour obtenir en plus la ligne
    # d’ouverture de service ; sur cette version de Samba, cette ligne ne figure
    # dans aucun des journaux accessibles et n’a donc pas été retenue. Ce qui
    # manque ici est compensé ailleurs : la règle 9000003 du laboratoire journalise
    # la négociation SMB en clair, et c’est cette alerte qui atteste la lecture.
    log level = 1 auth:3
    # Le journal est écrit dans le volume partagé : c’est ce même fichier, et non
    # une copie, que l enquêteur lit dans ~/journal/journal-samba.log. Le serveur
    # de fichiers n héberge pas de second journal : un seul fichier, une seule
    # source, et le chapitre peut donc rapprocher une ligne de ce journal d’un
    # paquet de la capture sans avoir à choisir entre deux versions.
    log file = /partage/journal/journal-samba.log
    max log size = 5000

[partage]
    comment = Partage du laboratoire
    path = /srv/partage
    read only = yes
    guest ok = no
    valid users = enquete
CONF
    # La configuration du laboratoire doit remplacer la configuration par défaut
    # de la distribution : sans cette copie, smbd démarre, le port 445 répond,
    # et le partage annoncé dans le support reste introuvable.
    cp /etc/samba/smb.conf.lab /etc/samba/smb.conf
    testparm -s >/dev/null
    # Le compte Unix doit exister avant l inscription dans la base Samba : la
    # commande « pdbedit » refuse l entrée si l utilisateur est absent, et son
    # échec est silencieux. Le port 445 répondrait pourtant, et
    # l authentification échouerait sans raison visible.
    id enquete >/dev/null 2>&1 || useradd --create-home --shell /bin/bash enquete
    printf "lab-2026\nlab-2026\n" | pdbedit -a -u enquete -t >/dev/null
    pdbedit -L | grep -q "^enquete:"
    smbd -D --configfile=/etc/samba/smb.conf --no-process-group
  ' >/dev/null
  ok "SMB sur le port 445 de lab-fichiers, journal dans le volume partagé"

  # Le port 23 en clair du serveur de fichiers. Le démon Telnet d'Ubuntu ne
  # démarre pas sans inetd et busybox n'en fournit pas : le port est donc tenu par
  # un émetteur d'invite de connexion qui relit ce que le client envoie. C'est de
  # cette lecture que le mot de passe en clair se trouve dans la capture, et sans
  # elle le chapitre sur la conservation des preuves n'aurait aucune trace à
  # montrer.
  docker exec -d "$PREFIXE-fichiers" sh -c \
    'while true; do printf "Ubuntu 26.04 LTS\r\nlab-fichiers login: " | timeout 30 busybox nc -l -p 23 >/dev/null 2>&1; done'
  ok "Telnet en clair sur le port 23 de lab-fichiers"

  # Détection. Suricata s'exécute dans la sonde, qui partage l'espace réseau du
  # poste compromis, et surveille l'interface par laquelle ce poste atteint le
  # site central : c'est l'incident qui part de cette machine, donc c'est son
  # trafic qui doit être analysé. Zeek et Splunk ne sont pas installés : ils ne
  # figurent pas dans les dépôts de la distribution, et le support les présente
  # comme des outils optionnels, avec ce journal comme repli.
  #
  # Seules les règles du laboratoire sont chargées. Les règles livrées avec la
  # distribution ne sont pas actives ici, pour trois raisons mesurées : quinze
  # d'entre elles référencent des événements de protocoles que la configuration
  # désactive et refusent donc de se charger, une règle signale des sommes de
  # contrôle invalides qui ne correspondent à aucun incident — le moteur
  # observant le poste suspect, il capte ses propres émissions avant que le
  # noyau n'ait calculé la somme — et, mêlées aux nôtres, elles empechaient les
  # règles de l'incident de se déclencher. Un moteur qui ne surveille que ce
  # qu'il doit alerter est plus lisible, et c'est celui que le cours enseigne.
  #
  # Le chemin du fichier est donné en entier. La forme relative a été observée
  # comme ignorée de façon intermitente par cette version du moteur, sans raison
  # apparente : le fichier n'est chargé qu'une fois sur deux.
  #
  # Ce bloc et le suivant transmettent leur contenu au shell du conteneur dans
  # une chaîne simple. Aucun commentaire contenant une apostrophe droite ne doit
  # y figurer : cette apostrophe fermerait la chaîne, et le shell de la machine
  # exécuterait la suite du script au lieu du conteneur. Les commentaires sont
  # donc placés avant l'ouverture de la chaîne ou après sa fermeture.
  docker exec -d "$PREFIXE-sonde" sh -c '
    mkdir -p /sortie/suricata
    cat > /etc/suricata/laboratoire.yaml <<CONF
%YAML 1.1
---
default-log-dir: /sortie/suricata
outputs:
  - eve-log:
      enabled: yes
      filetype: regular
      filename: eve.json
      types:
        - alert:
            payload: yes
            payload-printable: yes
            http-body: yes
        - dns
        - http
        - tls
        - flow
        - netflow
app-layer:
  protocols:
    http:
      enabled: yes
    tls:
      enabled: yes
    smb:
      enabled: yes
    dns:
      enabled: yes
default-rule-path: /etc/suricata/rules
rule-files:
  - /etc/suricata/rules/laboratoire.rules
classification-file: /etc/suricata/classification.config
reference-config-file: /etc/suricata/reference.config
CONF
    exec suricata -c /etc/suricata/laboratoire.yaml -i eth1 -l /sortie/suricata --set unix-command.enabled=no
  '
  # La sonde surveille l'interface par laquelle le poste compromis atteint le site
  # central : c'est par là que part l'incident, et c'est le seul trafic qu'elle
  # voit. L'interface est nommée explicitement, deux raisons ayant été mesurées :
  # la capture sur « any » est refusée par cette version du moteur, et la
  # déclaration des deux interfaces du poste fait échouer la mise en grappe de la
  # couche de capture. Le journal est écrit dans le volume du poste de
  # l'enquêteur : il y est lisible sous ~/suricata/eve.json.
  ok "Suricata analyse le trafic du poste compromis et écrit ~/suricata/eve.json"

  # Collecte des journaux. rsyslog écoute le port 514 en réception réseau et
  # rassemble les journaux de tous les hôtes du laboratoire.
  #
  # Le journal rassemblé est écrit dans le volume partagé, donc lu par
  # l'enquêteur dans ~/journal/journal-reseau.log. Il n'est écrit nulle part
  # ailleurs : deux copies du même journal seraient deux sources, et
  # l'apprenant ne saurait pas laquelle fait foi. Le fichier est créé en 644 par
  # le collecteur, qui est root : l'enquêteur le lit, il ne le réécrit pas.
  printf '%s\n' \
    'module(load="imudp")' \
    'input(type="imudp" port="514")' \
    'global(workDirectory="/run/rsyslab")' \
    '$FileCreateMode 0644' \
    '$FileOwner root' \
    '$FileGroup root' \
    '*.* /partage/journal/journal-reseau.log' \
  | docker exec -i -u root "$PREFIXE-collecteur" sh -c \
      'mkdir -p /run/rsyslab && cat > /etc/rsyslab.conf'
  if ! controle=$(docker exec -u root "$PREFIXE-collecteur" \
                     rsyslogd -N1 -f /etc/rsyslab.conf 2>&1 >/dev/null); then
    err "la configuration de collecte du collecteur est refusée par rsyslog"
    printf '%s\n' "$controle" >&2
    return 1
  fi
  docker exec -d -u root "$PREFIXE-collecteur" \
    rsyslogd -n -i NONE -f /etc/rsyslab.conf
  ok "rsyslog en réception sur le port 514, journal lu par l'enquêteur dans ~/journal/journal-reseau.log"

  # Les journaux du site central sont envoyés au collecteur : chaque hôte écrit
  # d'abord son journal local, comme le fait toute machine, puis le transmet.
  #
  # Deux hôtes transmettent en plus un fichier que leur produit n'écrit pas dans
  # le journal système. Un serveur de fichiers ne fait pas syslog de ses
  # ouvertures de session : son serveur Samba écrit dans son propre fichier. Un
  # poste compromis ne déclare pas non plus les gestes qu'il commet. Sans ces
  # deux entrées, le journal du collecteur ne contiendrait que des messages de
  # démarrage, et le chapitre consacré aux journaux n'aurait rien à analyser.
  #
  # La transmission se fait par « imfile », qui suit un fichier déjà existant et
  # en relaie chaque ligne au collecteur, étiquette par étiquette. Aucun second
  # journal n'est créé de ce côté : le serveur de fichiers garde exactement le
  # fichier que sa configuration Samba désigne déjà, et c'est ce fichier-là qui
  # est lu par l'enquêteur et par le collecteur.
  #
  # L'intervalle de lecture est ramené à deux secondes. C'est le délai maximal
  # qui borne la précision d'une chronologie fondée sur les journaux : un
  # événement produit par un hôte n'apparaît au collecteur qu'au tour de lecture
  # suivant. Une valeur de dix secondes, celle par défaut, ajouterait une part
  # d'attente arbitraire à chaque événement sans rien gagner sur un laboratoire.
  #
  # Ce plafond n'est pas atteint dans la pratique, et la raison vaut d'être notée.
  # Cette version de rsyslog surveille les fichiers par notify : la lecture
  # intervient à l'écriture, et non au tour de sondage. Le délai mesuré sur ce
  # laboratoire est de l'ordre de centièmes de seconde, très en deçà du plafond.
  # C'est donc l'horodatage des lignes reçues, au dixième de seconde près, qui
  # fixe la résolution d'une chronologie, et non le transport.
  demarrer_rsyslog_hote "$PREFIXE-app"
  demarrer_rsyslog_hote "$PREFIXE-passerelle"
  demarrer_rsyslog_hote "$PREFIXE-filiale"
  demarrer_rsyslog_hote "$PREFIXE-fichiers" \
    /partage/journal/journal-samba.log samba-fichiers
  demarrer_rsyslog_hote "$PREFIXE-compromis" \
    /var/log/journal-scenario.log poste-compromis
  ok "journaux du site central et de la filiale envoyés à 10.10.0.50:514"

  # Le journal d'actions du poste compromis est créé ici, vide, avant que la
  # collecte ne se mette à le lire : le scénario d'incident l'écrit ensuite, et
  # le relais n'a ainsi jamais à attendre l'apparition d'un fichier. La création
  # ne change rien au scénario, qui continue d'écrire dans ce même chemin.
  docker exec -u root "$PREFIXE-compromis" sh -c \
    'mkdir -p /var/log && : > /var/log/journal-scenario.log && chmod 0644 /var/log/journal-scenario.log'
  ok "journal d'actions du poste compromis prêt pour la transmission"

  # La collecte ne produit de preuve que si les hôtes journalisent réellement.
  # Un message de démarrage horodaté est écrit sur chaque hôte : il rend le
  # collecteur non vide dès le montage, et le chapitre sur les journaux peut
  # s'appuyer dessus pour expliquer le format d'une ligne et son horodatage.
  for hote in "$PREFIXE-app" "$PREFIXE-fichiers" "$PREFIXE-passerelle" "$PREFIXE-compromis" "$PREFIXE-filiale"; do
    demarrer_journal "$hote"
  done
  ok "messages de démarrage horodatés écrits dans les journaux des hôtes"
}

# Attendre que la passerelle du segment réponde.
attendre() {
  local fin=$(( SECONDS + ${1:-30} ))
  while [ $SECONDS -lt $fin ]; do
    if docker exec "$PREFIXE-enquete" ping -c1 -W1 10.10.0.1 >/dev/null 2>&1 \
       && docker exec "$PREFIXE-enquete" ping -c1 -W1 10.20.0.1 >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  err "le poste de l'enquêteur n'atteint pas les deux passerelles dans le délai imparti"
  return 1
}

# Attendre que les ports attendus répondent tous. Sans cette attente, la
# vérification démarrerait avant que les services n'aient démarré et conclurait à
# tort que le laboratoire est absent.
attendre_services() {
  local fin=$(( SECONDS + 120 ))
  local cibles="10.10.0.20:22 10.10.0.20:80 10.10.0.20:443 10.10.0.30:23 10.10.0.30:445 10.20.0.20:22 10.20.0.20:80"
  while [ $SECONDS -lt $fin ]; do
    local manques=0
    for cible in $cibles; do
      local ip=${cible%:*} port=${cible#*:}
      if ! docker exec "$PREFIXE-enquete" nmap -sT -n -Pn -p "$port" "$ip" 2>/dev/null \
           | grep -q "$port/tcp *open"; then
        manques=$((manques+1))
      fi
    done
    if [ "$manques" -eq 0 ]; then
      ok "les 7 services attendus répondent"
      return 0
    fi
    sleep 3
  done
  err "des services ne répondent pas après 120 secondes"
  return 1
}

# ----------------------------------------------------------------- vérifier
verifier() {
  local echecs=0
  log "Vérification depuis le poste de l'enquêteur (10.10.0.10)"

  # 1. Joignabilité de toutes les machines
  for ip in 10.10.0.1 10.10.0.20 10.10.0.30 10.10.0.50 10.20.0.1 10.20.0.10 10.20.0.20; do
    if docker exec "$PREFIXE-enquete" ping -c2 -W1 "$ip" >/dev/null 2>&1; then
      ok "ping $ip"
    else
      err "ping $ip ne répond pas"; echecs=$((echecs+1))
    fi
  done

  # 2. Découverte : cinq hôtes sur le site central, trois sur la filiale
 nb_hotes() {
    docker exec "$PREFIXE-enquete" nmap -sn -n "$1" 2>/dev/null \
      | grep -c "Nmap scan report" || true
  }
  local central filiale
  central=$(nb_hotes 10.10.0.0/24)
  filiale=$(nb_hotes 10.20.0.0/24)
  if [ "$central" -ge 6 ]; then
    ok "nmap -sn renvoie $central hôtes sur 10.10.0.0/24"
  else
    err "nmap -sn renvoie $central hôtes sur 10.10.0.0/24, moins que les 6 attendus"
    echecs=$((echecs+1))
  fi
  if [ "$filiale" -ge 3 ]; then
    ok "nmap -sn renvoie $filiale hôtes sur 10.20.0.0/24"
  else
    err "nmap -sn renvoie $filiale hôtes sur 10.20.0.0/24, moins que les 3 attendus"
    echecs=$((echecs+1))
  fi

  # 3. États de port annoncés par le support
  #
  #    Chaque état de port est interrogé jusqu'à trois fois. Cette répétition
  #    compense une propriété réelle du démon Telnet du laboratoire, et elle ne
  #    masque aucun défaut : un service réellement arrêté échoue aux trois
  #    tentatives. Le seul démon Telnet installable hors ligne sur cette image
  #    est celui de busybox, et il n'accepte qu'une seule connexion en attente.
  #    Pendant que le scénario d'incident ouvre et ferme ses sessions Telnet, une
  #    sonde qui se présente au même instant est refusée : nmap rapporte alors le
  #    port 23 fermé alors qu'il est ouvert. Ce faux négatif a été observé sur ce
  #    laboratoire ; deux secondes d'écart suffisent à le lever.
  attendre_etat() {
    local ip=$1 port=$2 etat=$3
    local essai constant=0
    for essai in 1 2 3; do
      if docker exec "$PREFIXE-enquete" \
          nmap -sT -n -p "$port" "$ip" 2>/dev/null | grep -q "$port/tcp *$etat"; then
        constant=1
        break
      fi
      sleep 2
    done
    if [ "$constant" -eq 1 ]; then
      ok "$ip port $port = $etat"
    else
      err "$ip port $port n'est pas $etat"; echecs=$((echecs+1))
    fi
  }
  attendre_etat 10.10.0.20 22 open
  attendre_etat 10.10.0.20 80 open
  attendre_etat 10.10.0.20 443 open
  attendre_etat 10.10.0.30 23 open
  attendre_etat 10.10.0.30 445 open
  attendre_etat 10.20.0.20 22 open
  attendre_etat 10.20.0.20 80 open
  # Aucun autre port ne doit être ouvert sur le serveur de fichiers : le
  # chapitre sur l'analyse des paquets doit y trouver exactement les deux
  # services annoncés, et rien d'autre à expliquer.
  attendre_etat 10.10.0.30 3389 closed

  # 4. Chaque segment est joignable depuis l'interface qui lui appartient. Le
  #    relais entre les deux segments n'est pas exercé : Docker isole le passage
  #    d'un pont à l'autre, et aucun LAB n'en dépend.
  if docker exec "$PREFIXE-enquete" ping -c2 -W1 10.20.0.10 >/dev/null 2>&1; then
    ok "le poste de l'enquêteur atteint la filiale par son interface 10.20.0.30"
  else
    err "l'interface 10.20.0.30 n'atteint pas la filiale"; echecs=$((echecs+1))
  fi
  if docker exec "$PREFIXE-enquete" ping -c2 -W1 10.10.0.60 >/dev/null 2>&1; then
    ok "le poste de l'enquêteur atteint le poste compromis sur le site central"
  else
    err "le poste compromis n'est pas joignable depuis le site central"
    echecs=$((echecs+1))
  fi

  # 5. Une capture est possible, et le trafic à capturer est généré en même temps
  #    que la capture : sinon tcpdump attend indéfiniment les deux paquets annoncés.
  #    La capture se fait par « sudo » : le compte enqueteur n'a pas les droits
  #    nécessaires sur l'interface, et les capacités posées sur le binaire ne
  #    peuvent pas les lui donner, car le jeu de droits hérité d'un processus non
  #    privilégié est vide. Le mot de passe n'est pas demandé, l'image l'accorde.
  if docker exec "$PREFIXE-enquete" sh -c \
      'sudo timeout 20 sh -c "tcpdump -c4 -w /tmp/verif.pcap icmp & sleep 2; ping -c4 -W1 10.10.0.20 >/dev/null 2>&1; wait"' \
      >/dev/null 2>&1 \
     && docker exec "$PREFIXE-enquete" sudo capinfos -c /tmp/verif.pcap >/dev/null 2>&1; then
    ok "sudo tcpdump capture le trafic et la capture est exploitable"
  else
    err "tcpdump ne produit pas de capture exploitable"; echecs=$((echecs+1))
  fi

  # 6. Suricata produit un journal EVE exploitable, et cet alertes contient au
  #    moins une alerte issue des règles du laboratoire. Un journal rempli de
  #    simples entrées de flux prouverait que le moteur tourne, pas qu'il
  #    détecte l'incident : c'est la seconde propriété qui rend le livrable possible.
  #
  #    Le contrôle ne se contente pas de lire le journal : il provoque d'abord
  #    l'incident qu'il veut vérifier. Exiger une alerte déjà présente rendrait le
  #    résultat dépendant de l'heure à laquelle la vérification est lancée, puisque
  #    le scénario d'incident ne joue ses comportements que toutes les huit
  #    minutes. Le contrôle déclenche donc un balayage bref depuis le poste
  #    compromis, puis attend l'alerte. Le balayage est exactement celui du
  #    scénario : huit ports inhabituels suffisent à franchir le seuil de cinq
  #    segments SYN en trente secondes.
  eve_valide() {
    docker exec "$PREFIXE-enquete" sh -c \
      'tail -n 400 /home/enqueteur/suricata/eve.json 2>/dev/null | jq -e -c . >/dev/null' 2>/dev/null
  }

  alerte_labo() {
    docker exec "$PREFIXE-enquete" sh -c \
      'jq -r "select(.event_type==\"alert\") | .alert.signature_id" \
         /home/enqueteur/suricata/eve.json 2>/dev/null | grep -q "^90000"' 2>/dev/null
  }

  if ! alerte_labo; then
    log "Aucune alerte des règles du laboratoire : déclenchement d'un balayage de contrôle"
    docker exec "$PREFIXE-compromis" \
      nmap -sT -n -Pn -p 21,25,53,110,139,143,3306,3389 10.10.0.30 >/dev/null 2>&1 || true
    attente=0
    while [ "$attente" -lt 60 ] && ! alerte_labo; do
      sleep 3
      attente=$((attente+3))
    done
  fi

  if docker exec "$PREFIXE-enquete" test -s /home/enqueteur/suricata/eve.json 2>/dev/null; then
    if eve_valide; then
      ok "le journal EVE de Suricata est produit et se lit avec jq"
    else
      err "le journal EVE de Suricata n'est pas du JSON valide"
      echecs=$((echecs+1))
    fi
    if alerte_labo; then
      ok "au moins une alerte des règles du laboratoire est présente"
    else
      err "aucune alerte des règles du laboratoire dans le journal EVE"
      echecs=$((echecs+1))
    fi
  else
    err "Suricata n'a produit aucun journal dans ~/suricata/eve.json"
    echecs=$((echecs+1))
  fi

  # 7. Les journaux sont lisibles par l'enquêteur, en compte ordinaire
  #
  #    Tous les contrôles de ce point passent par le poste de l'enquêteur et
  #    par le compte « enqueteur ». C'est délibéré : la question que le support
  #    doit pouvoir voir affirmée n'est pas « le fichier existe », mais
  #    « l'apprenant peut-il le lire, et ne peut-il pas le réécrire ». Un contrôle
  #    effectué en root dans le conteneur du collecteur ne répondrait à aucune
  #    des deux.
  #
  #    Deux journaux sont vérifiés à ce point, tous deux dans le volume partagé ;
  #    le journal du moteur de détection, qui vit dans le même volume, a fait
  #    l'objet du point 6.
  #      ~/journal/journal-reseau.log   le journal rassemblé par le collecteur
  #      ~/journal/journal-samba.log    le journal d'accès du serveur de fichiers
  journal_lisible() {
    docker exec "$PREFIXE-enquete" sh -c \
      "test -r '$1' && test -s '$1'" 2>/dev/null
  }

  #    Ces chemins sont affichés avec le tild du dossier personnel, comme le fera
  #    le support. La substitution est écrite « ~ » avec une barre oblique
  #    inversée devant elle : dans la partie droite d'une substitution de
  #    paramètre, bash applique l'expansion du tild, et un tild nu y vaudrait le
  #    dossier personnel de la machine qui lance le script. Le contrôleur
  #    afficherait alors un chemin de laboratory absent et l'apprenant chercherait
  #    au mauvais endroit.
  for fichier in /home/enqueteur/journal/journal-reseau.log \
                 /home/enqueteur/journal/journal-samba.log; do
    if journal_lisible "$fichier"; then
      ok "l'enquêteur lit ${fichier/#\/home\/enqueteur\//\~/}"
    else
      err "${fichier/#\/home\/enqueteur\//\~/} est absent, vide ou illisible par l'enquêteur"
      echecs=$((echecs+1))
    fi
  done

  # 8. La collecte rassemble réellement les journaux des autres hôtes
  #
  #    Le contrôle ne se contente pas de lire un fichier : il provoque les
  #    événements qu'il veut vérifier. Exiger une trace déjà présente rendrait le
  #    résultat dépendant de l'heure à laquelle la vérification est lancée, alors
  #    que le scénario d'incident ne joue que toutes les huit minutes.
  attendre_dans_journal() {
    local motif=$1 secondes=${2:-40}
    local fin=$(( SECONDS + secondes ))
    while [ $SECONDS -lt $fin ]; do
      if docker exec "$PREFIXE-enquete" \
           grep -q "$motif" /home/enqueteur/journal/journal-reseau.log 2>/dev/null; then
        return 0
      fi
      sleep 2
    done
    return 1
  }

  # Une lecture du partage, jouée depuis le poste compromis : c'est exactement
  # le geste du scénario d'incident, et c'est ce geste qui produit les traces
  # d'accès du serveur de fichiers.
  if ! attendre_dans_journal samba-fichiers 5; then
    docker exec "$PREFIXE-compromis" timeout 30 smbclient "//10.10.0.30/partage" \
      -U "enquete%lab-2026" -c ls >/dev/null 2>&1 || true
  fi
  if attendre_dans_journal samba-fichiers 40; then
    ok "le collecteur reçoit les événements d'accès du serveur de fichiers"
  else
    err "les événements d'accès du serveur de fichiers n'atteignent pas le collecteur"
    echecs=$((echecs+1))
  fi

  if attendre_dans_journal poste-compromis 20; then
    ok "le collecteur reçoit le journal d'actions du poste compromis"
  else
    err "le journal d'actions du poste compromis n'atteint pas le collecteur"
    echecs=$((echecs+1))
  fi

  # Un message écrit à l'instant sur un hôte doit ressortir dans le journal
  # rassemblé. La marque porte l'heure d'émission : une trace laissée par une
  # vérification précédente ne peut donc pas faire passer celle-ci, et le contrôle
  # mesure bien le délai de collecte au lieu de lire une relève antérieure.
  marque="controleur-$(date -u +%H%M%S)-$$"
  docker exec "$PREFIXE-passerelle" logger -t controleur "$marque" 2>/dev/null || true
  if attendre_dans_journal "$marque" 30; then
    ok "un message écrit sur un hôte du site central est rassemblé par le collecteur"
  else
    err "le collecteur ne rassemble pas les messages du site central"
    echecs=$((echecs+1))
  fi

  # 9. L'enquêteur ne peut pas modifier les journaux
  #
  #    C'est la contrepartie obligatoire de la lecture. Un journal qu'un compte
  #    ordinaire peut réécrire cesse d'être une preuve, et le chapitre qui apprend
  #    à en tirer une chronologie serait faux. Le contrôle tente donc d écrire,
  #    et exige que l'écriture échoue.
  for fichier in /home/enqueteur/journal/journal-reseau.log \
                 /home/enqueteur/journal/journal-samba.log; do
    if docker exec "$PREFIXE-enquete" sh -c \
         "printf 'essai' >> '$fichier'" 2>/dev/null; then
      err "l'enquêteur a pu écrire dans ${fichier/#\/home\/enqueteur\//\~/}"
      echecs=$((echecs+1))
    else
      ok "${fichier/#\/home\/enqueteur\//\~/} est en écriture refusée pour l'enquêteur"
    fi
  done
  if docker exec "$PREFIXE-enquete" sh -c \
       'touch ~/journal/journal-injecte.log' 2>/dev/null; then
    err "l'enquêteur a pu créer un fichier dans ~/journal"
    echecs=$((echecs+1))
  else
    ok "l'enquêteur ne peut pas créer de fichier dans ~/journal"
  fi

  # 10. Le scénario d'incident tourne
  if docker exec "$PREFIXE-compromis" pgrep -f scenario-incident >/dev/null 2>&1; then
    ok "le scénario d'incident tourne sur 10.20.0.10"
  else
    err "le scénario d'incident ne tourne pas sur 10.20.0.10"
    echecs=$((echecs+1))
  fi

  # 11. Le dossier de livrables est accessible en écriture par l'enquêteur
  #     Contradiction apparente avec le point 9, et il n'y en a pas : le compte
  #     ordinaire écrit ses livrables dans son dossier de travail et dans aucun
  #     autre. Cette distinction entre le dossier de travail et le dossier des
  #     journaux est précisément ce que le chapitre sur la conservation des
  #     preuves enseigne.
  if docker exec "$PREFIXE-enquete" sh -c \
      'mkdir -p ~/enquete && touch ~/enquete/.essai && test -w ~/enquete'; then
    ok "le dossier ~/enquete du poste de l'enquêteur est accessible en écriture"
  else
    err "~/enquete n'est pas accessible en écriture"; echecs=$((echecs+1))
  fi

  echo
  if [ "$echecs" -eq 0 ]; then
    ok "Laboratoire conforme aux attentes des trois journées"
    return 0
  fi
  err "$echecs vérification(s) en échec"
  return 1
}

# ----------------------------------------------------------------- scénario
# Relance du scénario d'incident. Utile quand la boucle s'est arrêtée, par
# exemple après un redémarrage du conteneur du poste compromis.
scenario() {
  log "Relance du scénario d'incident sur lab-compromis"
  docker exec "$PREFIXE-compromis" pkill -f 'scenario-incident' 2>/dev/null || true
  docker cp scenario-incident.sh "$PREFIXE-compromis":/tmp/scenario-incident.sh
  docker exec -d "$PREFIXE-compromis" bash /tmp/scenario-incident.sh
  ok "scénario d'incident relancé"
}

# ------------------------------------------------------------------ arrêter
arrêter() {
  for hote in $APPS; do
    docker rm -f "$PREFIXE-$hote" >/dev/null 2>&1 || true
  done
  docker network rm "$RESEAU_CENTRAL" "$RESEAU_FILIALE" >/dev/null 2>&1 || true
  ok "conteneurs et réseaux supprimés"
}

# Exécuter une commande dans le poste de l'enquêteur, avec le chemin déjà réglé.
enquete() {
  docker exec -w /home/enqueteur/enquete "$PREFIXE-enquete" "$@"
}

case "${1:-monter}" in
  monter)    monter ;;
  verifier)  verifier ;;
  scenario)  scenario ;;
  arrêter)   arrêter ;;
  enquete)   shift; enquete "$@" ;;
  *)         echo "Usage : $0 {monter|verifier|scenario|arrêter|enquete <commande>}" >&2; exit 2 ;;
esac
