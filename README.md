# Forensique réseau — Formation DGFIP

Formation de 3 jours en forensique réseau (présentielle à Paris), dispensée pour la DGFIP par Ascent.

## Sommaire

### [Jour 1 — Lundi 12 octobre 2026](jour-1.md)
- **Chapitre 1 — M1 : Introduction à la forensique réseau** (9h00 – 11h00)
- **Chapitre 2 — M2 : Capture et collecte des données réseau** (11h00 – 12h00 et 13h00 – 16h00)

### [Jour 2 — Mardi 13 octobre 2026](jour-2.md)
- **Chapitre 3 — M3 : Analyse des paquets et détection des anomalies** (9h00 – 12h00)
- **Chapitre 4 — M4 : Utilisation des journaux et des outils d'analyse réseau** (13h00 – 16h00)

### [Jour 3 — Mercredi 14 octobre 2026](jour-3.md)
- **Chapitre 5 — M5 : Réponse aux incidents de sécurité réseau** (9h00 – 12h00)
- **Chapitre 6 — M6 : Rédaction du rapport d'enquête réseau** (13h00 – 16h00)

### [Sous-cours de remise à niveau](extra.md)
Remise à niveau Linux et tcpdump pour préparer l'environnement de laboratoire.

### [Laboratoire](lab/)
Scripts et règles du laboratoire d'enquête réseau :
- [construire-lab.sh](lab/construire-lab.sh) — construction et démarrage de l'environnement
- [regles-detection.rules](lab/regles-detection.rules) — règles de détection Suricata
- [telecharger-paquets.sh](lab/telecharger-paquets.sh) — téléchargement des captures de référence

## Environnement de laboratoire

- Réseau site central : `10.10.0.0/24`
- Réseau filiale : `10.20.0.0/24`
- Poste enquêteur : `10.10.0.10`
- Collecteur/serveurs : `10.10.0.20`, `10.10.0.30`, `10.10.0.50`, `10.20.0.10`, `10.20.0.20`
