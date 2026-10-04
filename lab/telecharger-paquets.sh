#!/usr/bin/env bash
# Télécharge, sur l'hôte, tous les paquets .deb dont l'image du laboratoire a
# besoin. Les conteneurs n'ont pas accès à Internet sur cette machine : c'est
# donc l'hôte qui résout et télécharge, et l'image s'installe ensuite hors ligne.
#
# `apt-get install --download-only` est écarté volontairement : cette commande
# verrouille /var/lib/dpkg, échoue si une autre opération de paquets est en
# cours, et exige les droits de superutilisateur. On passe donc par la
# résolution en lecture seule suivie d'un téléchargement paquet par paquet, ce
# qui fonctionne avec un compte ordinaire et sans toucher à l'état du système.
#
# Usage : ./telecharger-paquets.sh [répertoire-de-sortie]
set -euo pipefail

DEST="${1:-$(cd "$(dirname "$0")" && pwd)/debs}"
mkdir -p "$DEST"

# Liste des outils du programme, plus les services des hôtes simulés.
PAQUETS=(
  # outillage réseau
  iproute2 iputils-ping nmap iperf3 tcpdump tshark wireshark
  # moteurs de détection et collecte des journaux
  suricata rsyslog jq python3
  # services des hôtes du laboratoire
  openssh-server openssl samba smbclient
  # utilitaires
  procps netcat-openbsd busybox sudo nano inetutils-telnet
)

LISTE="$(mktemp)"
FILTRE="$(mktemp)"
TMP="$(mktemp -d)"
# shellcheck disable=SC2064
trap 'rm -f "$LISTE" "$FILTRE"; rm -rf "$TMP"' EXIT

echo "Résolution des dépendances sur l'hôte"

# apt-cache travaille en lecture seule : aucune clé n'est demandée, aucun
# verrou n'est posé sur la base de paquets.
apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts \
  --no-breaks --no-replaces --no-enhances "${PAQUETS[@]}" 2>/dev/null \
  | grep -E '^[a-zA-Z0-9]' \
  | sed 's/:amd64$//' \
  | sort -u > "$LISTE"

# Seules les architectures natives sont retenues. La résolution récursive
# propose aussi les paquets i386 d'interopérabilité, qu'une installation globale
# fait échouer sur une machine amd64 : ils sont donc écartés explicitement.
ARCH="$(dpkg --print-architecture)"
grep -E "^[^:]+(:$ARCH)?$" "$LISTE" > "$FILTRE" || true

NB_ATTENDU=$(wc -l < "$FILTRE")
echo "$NB_ATTENDU paquets à télécharger dans $DEST"

MANQUANTS=0
cd "$TMP"

while read -r paquet; do
  [ -z "$paquet" ] && continue
  # Un paquet déjà présent est ignoré : le téléchargement est reprenable.
  if [ -f "$DEST/${paquet}_${ARCH}.deb" ] || [ -f "$DEST/${paquet}_all.deb" ]; then
    continue
  fi
  if ! apt-get download "$paquet" >/dev/null 2>&1; then
    echo "  impossible à télécharger $paquet" >&2
    MANQUANTS=$((MANQUANTS+1))
  fi
done < "$FILTRE"

find "$TMP" -maxdepth 1 -name '*.deb' -exec mv -t "$DEST" {} + 2>/dev/null || true

NB=$(find "$DEST" -maxdepth 1 -name '*.deb' | wc -l)
TAILLE=$(du -sh "$DEST" | cut -f1)
echo "$NB paquets présents dans $DEST, $TAILLE au total"

if [ "$MANQUANTS" -gt 0 ]; then
  echo "$MANQUANTS paquet(s) non téléchargés : vérifier l'accès aux dépôts" >&2
  exit 1
fi