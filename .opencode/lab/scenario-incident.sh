#!/usr/bin/env bash
# Générateur de l'incident du laboratoire « Forensique réseau ».
#
# Ce script est exécuté dans le conteneur du poste compromis (10.20.0.10 sur le
# segment de la filiale, 10.10.0.60 sur le segment du site central). Il rejoue en
# boucle les comportements qui fondent l'enquête des trois jours, à faible
# intensité pour ne pas perturber la machine du formateur.
#
# Toutes les cibles sont sur le segment du site central : c'est là que le poste de
# l'enquêteur et le moteur de détection observent le trafic, sans qu'aucun LAB
# n'ait besoin du relais entre les deux segments.
#
# Ce qu'il produit, et ce que le support en tirera :
#
#   1. Un balayage des ports du serveur de fichiers 10.10.0.30, à partir de la
#      filiale. C'est l'anomalie que le chapitre sur l'analyse des paquets devra
#      repérer, et le filtre BPF du support le targeted directement.
#   2. Des tentatives de connexion Telnet en clair vers 10.10.0.30, avec un
#      couple identifiant et mot de passe transmis sans chiffrement. La capture
#      contient donc le mot de passe en clair : c'est la preuve que le support
#      utilisera pour enseigner la conservation des preuves.
#   3. Une lecture de partage sur 10.10.0.30, qui produit des enregistrements
#      d'accès dans le journal du serveur de fichiers.
#   4. Un flot de paquets ICMP vers 10.10.0.20, qui correspond à la campagne de
#      déni de service étudiée au chapitre sur les anomalies.
#
# Un cinquième comportement, propre à la filiale, sert de témoin : le poste
# compromis balaie aussi le serveur de la filiale. Le chapitre sur l'analyse des
# paquets Constatera alors que la même adresse produit deux activités différentes
# selon le segment observé, ce qui est la démonstration que l'adresse seule ne
# suffit pas à caractériser un flux.
#
# Aucune de ces commandes ne sort du laboratoire : toutes les adresses sont
# celles des deux segments de l'image, et le mot de passe est une valeur de
# laboratoire documentée dans le tableau d'environnement du support.
set -u

CIBLE_FICHIERS="10.10.0.30"
CIBLE_APPLI="10.10.0.20"
CIBLE_FILIALE="10.20.0.20"
PORT_TELNET=23
PORT_SMB=445
PARTAGE="partage"
COMPTE_SMB="enquete"
MOT_DE_PASSE_SMB="lab-2026"

# journaliser écrit une ligne horodatée à deux endroits : sur la sortie standard,
# reprise par « docker logs », et dans un fichier du conteneur. Le fichier est
# indispensable, car « docker exec -d » détache le processus sans lui laisser de
# sortie attached : sans ce fichier, rien ne prouverait que le scénario tourne, et
# une erreur de commande resterait invisible. Le fichier est de surcroît une
# horloge de l'incident : il date chaque comportement observé.
journaliser() {
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" \
        | tee -a "${JOURNAL_SCENARIO:-/var/log/journal-scenario.log}"
}

# --- 1. Balayage des ports -----------------------------------------------------
balayer() {
    journaliser "balayage de $CIBLE_FICHIERS depuis 10.10.0.60"
    # -sT : Balayage TCP connecté. Il produit des connexions complètes, donc un
    # SYN suivi d'un SYN-ACK puis d'un ACK. Un balayage SYN produit un SYN sans
    # réponse pour chaque port fermé : la différence entre les deux est l'un des
    # points que le chapitre sur l'analyse des paquets doit faire constater.
    # Le poste compromis a deux interfaces : eth1 porte 10.10.0.60 (site central),
    # eth0 porte 10.20.0.10 (filiale). Pour atteindre 10.10.0.30 sur le site central,
    # on doit utiliser l'interface eth1.
    nmap -sT -n -Pn -e eth1 --max-retries 1 --host-timeout 20s \
         -p 21,22,23,25,53,80,110,139,143,443,445,993,995,3306,3389 \
         "$CIBLE_FICHIERS" 2>/dev/null || true
}

# Le même balayage, lancé depuis l'interface de la filiale. Il produit une
# activité de la même adresse qui n'apparaît que sur le segment de la filiale.
balayer_filiale() {
    journaliser "balayage de $CIBLE_FILIALE depuis 10.20.0.10"
    # Pour atteindre 10.20.0.20 sur le segment de la filiale, on utilise eth0
    # qui porte l'adresse 10.20.0.10.
    nmap -sT -n -Pn -e eth0 --max-retries 1 --host-timeout 20s \
         -p 21,22,23,80,443 "$CIBLE_FILIALE" 2>/dev/null || true
}

# --- 2. Connexion Telnet en clair ----------------------------------------------
# Le démon Telnet d'Ubuntu ne démarre pas sans inetd, et busybox n'en fournit
# pas. Le port 23 est donc tenu par un émetteur d'invite qui relit ce que le
# client envoie : c'est de cette lecture que le mot de passe en clair se trouve
# dans la capture. Sans ce composant, le chapitre sur la conservation des
# preuves n'aurait aucune trace à montrer.
tentative_telnet() {
    local essai=$1
    journaliser "tentative Telnet $essai vers $CIBLE_FICHIERS:$PORT_TELNET"
    {
        # La session Telnet commence par une négociation d'options, puis l'hôte
        # présente son invite. Le client répond, et le mot de passe suit en
        # clair sur le même lien.
        printf '\xff\xfd\x18\xff\xfd\x20\xff\xfd\x23\xff\xfd\x27'
        sleep 1
        printf 'root\r\n'
        sleep 1
        # Valeur de laboratoire, jamais celle d'un système réel.
        printf 'admin2026\r\n'
        sleep 1
        printf '\r\n'
    } | timeout 12 busybox nc "$CIBLE_FICHIERS" "$PORT_TELNET" 2>/dev/null || true
}

# --- 3. Lecture d'un partage ---------------------------------------------------
lire_partage() {
    journaliser "lecture du partage $PARTAGE sur $CIBLE_FICHIERS:$PORT_SMB"
    # L'authentification SMB transfère le couple en clair. Le serveur de
    # fichiers journalise la connexion : le chapitre consacré aux journaux
    # rapprochera cette ligne du flux observé dans la capture.
    timeout 20 smbclient "//$CIBLE_FICHIERS/$PARTAGE" \
        -U "$COMPTE_SMB%$MOT_DE_PASSE_SMB" -c 'ls' 2>/dev/null || true
}

# --- 4. Flot de déni de service ------------------------------------------------
# Le débit est volontairement bas : ce qui intéresse le cours est la forme du
# trafic observable dans une capture, pas la saturation du lien.
flot_icmp() {
    local paquet=$((100 + RANDOM % 200))
    journaliser "flot ICMP vers $CIBLE_APPLI, $paquet paquets"
    for _seq in $(seq 1 "$paquet"); do
        ping -c1 -W1 "$CIBLE_APPLI" >/dev/null 2>&1
    done
}

# --- Boucle principale ---------------------------------------------------------
# Chaque comportement est joué une fois toutes les huit minutes. Le délai est
# assez long pour que les journaux restent lisibles dans les trois journées, et
# assez court pour qu'un apprenant qui commence un LAB tard trouve toujours une
# activité à observer.
journaliser "scénario d'incident démarré sur $(hostname)"
while true; do
    balayer
    sleep 20
    tentative_telnet 1
    sleep 10
    tentative_telnet 2
    sleep 10
    lire_partage
    sleep 15
    flot_icmp
    sleep 10
    balayer_filiale
    journaliser "tour terminé, nouveau tour dans 8 minutes"
    sleep 480
done