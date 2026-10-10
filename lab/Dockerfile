# Image du laboratoire « Forensique réseau »
#
# Les conteneurs n'ont pas accès à Internet sur la machine de construction :
# tous les paquets sont téléchargés au préalable sur l'hôte par
# telecharger-paquets.sh, puis installés ici hors ligne avec dpkg.
#
# Contient exactement les outils annoncés dans CONTEXT.md :
#   iproute2               ip, ss, tc
#   iputils-ping           ping
#   nmap                   découverte d'hôtes et sondage des ports
#   iperf3                 génération d'un trafic connu pour une capture propre
#   tcpdump                capture et filtres BPF
#   tshark                 analyse d'une capture en ligne de commande
#   wireshark              analyse visuelle
#   suricata               moteur de détection, journaux au format EVE JSON
#   rsyslog                collecte des journaux du réseau
#   jq                     lecture des journaux JSON de Suricata
#   python3                scripts de dépouillement des journaux
#   samba, smbclient       serveur de fichiers et client, port 445 en clair
#   openssh-server         service de gestion sur le port 22
#   openssl                session TLS de démonstration sur le port 443
#
# Zeek et Splunk ne sont pas dans les dépôts de distribution : ils ne sont pas
# installés ici. Le support les présente comme des outils optionnels et fournit
# les journaux EVE de Suricata comme repli exécutable.
FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN=true

# Neutralisation du démarrage automatique des services : ces paquets lancent un
# service au premier démarrage, ce qui n'a pas lieu dans une image de laboratoire.
# Les services sont démarrés à la main par le constructeur, un par un, pour que
# chaque port annoncé dans le support corresponde exactement à un service réel.
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d

COPY debs /tmp/debs

# Installation hors ligne. dpkg traite les paquets dans l'ordre alphabétique et
# ne réessaie pas, dans le même appel, ceux dont une dépendance arrive plus loin
# dans la liste : trois passages suffisent à lever l'ordre, puis
# « dpkg --configure -a » termine la configuration.
RUN set -eu; \
   for essai in 1 2 3; do \
       dpkg -i /tmp/debs/*.deb >> /tmp/dpkg.log 2>&1 || true; \
   done; \
   dpkg --configure -a >> /tmp/dpkg.log 2>&1 || true; \
   rm -rf /tmp/debs /var/lib/apt/lists/* /tmp/dpkg.log

# Nettoyage : ni documentation ni traductions, l'image sert à exécuter des
# commandes, pas à consulter des pages de manuel.
RUN find /usr/share/doc /usr/share/man /usr/share/info /usr/share/locale \
       -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null || true \
 && apt-get clean

# Certificat de démonstration du serveur applicatif. Il est généré ici, dans
# l'image, et n'existe dans aucun fichier du dépôt : la clé privée qui accompagne
# ce certificat est un artefact de laboratoire, jamais un secret d'un système
# réel. Le support ne la montre pas et ne demande pas de la lire.
RUN set -eu; \
   mkdir -p /etc/lab \
 && openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout /etc/lab/cle-filiale.pem -out /etc/lab/cert-filiale.pem \
        -subj "/CN=serveur-filiale.laboratoire.invalid" >/dev/null 2>&1 \
 && chmod 600 /etc/lab/cle-filiale.pem

# Compte de l'enquêteur. Le support suppose un utilisateur ordinaire qui élève
# ses droits quand la capture l'exige : sans ce compte, les commandes écrites
# avec « sudo » ne seraient jamais exécutées dans les conditions réelles, et la
# différence entre compte ordinaire et compte privilégié resterait invisible.
#
# Le mot de passe n'est jamais stocké : l'accès à « sudo » est accordé par une
# règle sudoers explicite, valable uniquement dans cette image de laboratoire.
RUN useradd --create-home --shell /bin/bash --user-group enqueteur
RUN mkdir -p /home/enqueteur/enquete && chown -R enqueteur:enqueteur /home/enqueteur
RUN printf 'enqueteur ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/enqueteur \
 && chmod 0440 /etc/sudoers.d/enqueteur

# L'apprenant travaille en compte ordinaire et lance ses captures par « sudo ».
# Aucune capacité n'est posée sur le binaire tcpdump : cela ne fonctionnerait
# pas. Un fichier de capacités n'accorde ses droits que dans la mesure du jeu de
# droits déjà hérité par le processus, et ce jeu est vide pour un utilisateur non
# privilégié. Poser des capabilities sur un binaire donne donc l'illusion que la
# commande fonctionne sans privilège, alors qu'elle échoue avec « operation not
# permitted ». Le compte enqueteur dispose d'un sudo sans mot de passe, ce qui est
# la pratique normale d'un poste d'enquête, et ce que le support annonce.
RUN set -eu; \
    if getcap /usr/bin/tcpdump | grep -q .; then \
        echo "CAPACITE INATTENDUE SUR TCPDUMP"; exit 1; \
    fi; \
    grep -q '^enqueteur ALL=(ALL) NOPASSWD:ALL' /etc/sudoers.d/enqueteur \
      || { echo "SUDO SANS MOT DE PASSE ABSENT"; exit 1; }

# Règles de détection de l'incident du laboratoire. Les règles installées avec
# Suricata ne couvrent que des événements techniques : elles surveillent la
# correction du moteur, pas l'activité du réseau. Le fichier fournit donc les
# règles qui produisent les alertes attendues par le chapitre consacré aux
# journaux. Il est vérifié à la construction : une règle invalide ferait
# échouer le démarrage du moteur en silence.
COPY regles-detection.rules /etc/suricata/rules/laboratoire.rules
RUN suricata -T -c /etc/suricata/suricata.yaml \
      -S /etc/suricata/rules/laboratoire.rules -l /tmp \
   || { echo "REGLE DE DETECTION INVALIDE"; exit 1; }

# Vérification : chaque outil annoncé doit être présent, sinon la construction
# échoue. Le compte de l'enquêteur est vérifié lui aussi, car le cours lui fait
# utiliser les mêmes commandes : un outil visible seulement par root masquerait
# un défaut du laboratoire.
RUN set -eu; \
    for outil in ip ss ping nmap iperf3 tcpdump tshark suricata rsyslogd jq \
                 python3 sha256sum openssl smbd smbclient sshd busybox nc telnet \
                 nano; do \
        command -v "$outil" >/dev/null || { echo "OUTIL MANQUANT : $outil"; exit 1; }; \
    done; \
    id enqueteur >/dev/null 2>&1 || { echo "COMPTE enqueteur ABSENT"; exit 1; }; \
    command -v wireshark >/dev/null || { echo "OUTIL MANQUANT : wireshark"; exit 1; }; \
    echo "Tous les outils annoncés dans le programme sont présents"

WORKDIR /home/enqueteur/enquete
CMD ["sleep", "infinity"]