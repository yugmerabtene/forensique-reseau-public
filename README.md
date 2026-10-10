# Forensique réseau — Formation DGFIP

Formation de trois jours en **forensique réseau** pour la **DGFIP**, dispensée en
présentiel à **Paris** par le prestataire **Ascent**, les **12, 13 et 14 octobre
2026**, à raison de six heures par jour, soit dix-huit heures.

Le support se lit comme un livre : chaque journée porte deux chapitres, chacun
adossé à un module du syllabus. On explique avant de montrer, on nomme les mots,
puis on met les mains sur le clavier. Toutes les commandes, tous les filtres et
tout le laboratoire ont été testés ; les réseaux employés sont des réseaux
d’essai, et aucune donnée réelle du client n’y figure.

## Sommaire

### Jour 1 — Poser le cadre de l’enquête et prendre la première capture (12/10/2026)

Fichier complet : [`jour-1.md`](jour-1.md)

- [Chapitre 1 — M1 : Introduction à la forensique réseau](jour-1.md#chapitre-1--m1--introduction-à-la-forensique-réseau-9h0011h00)
- [Chapitre 2 — M2 : Capture et collecte des données réseau](jour-1.md#chapitre-2--m2--capture-et-collecte-des-données-réseau-11h0012h00-et-13h0016h00)

### Jour 2 — Les traces de l’incident (13/10/2026)

Fichier complet : [`jour-2.md`](jour-2.md)

- [Chapitre 3 — M3 : Analyse des paquets et détection des anomalies](jour-2.md#chapitre-3--m3--analyse-des-paquets-et-détection-des-anomalies-9h0012h00)
- [Chapitre 4 — M4 : Utilisation des journaux et des outils d’analyse réseau](jour-2.md#chapitre-4--m4--utilisation-des-journaux-et-des-outils-danalyse-réseau-13h0016h00)

### Jour 3 — Répondre à l’incident et rédiger le rapport d’enquête (14/10/2026)

Fichier complet : [`jour-3.md`](jour-3.md)

- [Chapitre 5 — M5 : Répondre à un incident de sécurité réseau](jour-3.md#chapitre-5--m5--répondre-à-un-incident-de-sécurité-réseau-9h0012h00)
- [Chapitre 6 — M6 : Rédiger le rapport d’enquête réseau](jour-3.md#chapitre-6--m6--rédiger-le-rapport-denquête-réseau-13h0016h00)

## Environnement de laboratoire

Un seul jeu de réseaux sert les trois journées, ce qui permet à l’apprenant de
reconnaître les mêmes machines d’un chapitre à l’autre.

| Élément | Valeur |
|---------|--------|
| Réseau du site central | `10.10.0.0/24` |
| Réseau de la filiale | `10.20.0.0/24` |
| Poste de l’enquêteur | `10.10.0.10`, compte ordinaire `enqueteur` |
| Passerelle du site central | `10.10.0.1` |
| Serveur applicatif | `10.10.0.20` — ports 22, 80 et 443 ouverts |
| Serveur de fichiers | `10.10.0.30` — port 23 en clair et 445 |
| Collecteur de journaux | `10.10.0.50` — syslog, Suricata, Zeek |
| Poste compromis | `10.20.0.10` — origine de l’incident |
| Serveur de la filiale | `10.20.0.20` — ports 22 et 80 ouverts |

Le laboratoire est un ensemble de machines isolées, monté une seule fois par le
formateur depuis la racine du projet :

```bash
lab/construire-lab.sh monter
```

## La chaîne des livrables

Le livrable d’un chapitre est la matière première du suivant, et le rapport du
jour 3 repose sur les cinq livrables produits les deux premiers jours.

| Jour | Chapitre | Livrable | Consommé par |
|------|----------|----------|--------------|
| J1 | C1 — M1 | `cadre-enquete.md` : périmètre, types de données, conservation | C2 |
| J1 | C2 — M2 | `capture-reference.pcap` : capture de référence horodatée | C3 et C4 |
| J1 | C2 — M2 | `inventaire-hotes.txt` : hôtes, ports et protocoles observés | C3 |
| J2 | C3 — M3 | `anomalies.md` : anomalies constatées et filtre qui les prouve | C4 et C5 |
| J2 | C4 — M4 | `alertes-suricata.txt` : alertes du moteur de détection | C5 |
| J3 | C5 — M5 | `chronologie-incident.md` : chronologie, vecteur, périmètre | C6 |
| J3 | C6 — M6 | `rapport-enquete.md` : rapport d’enquête complet | restitution finale |

## Le laboratoire

Le code complet du laboratoire est reproduit et commenté dans les annexes des
chapitres. Les fichiers sources se trouvent dans le répertoire [`lab/`](lab) :

| Fichier | Rôle |
|---------|------|
| [`lab/construire-lab.sh`](lab/construire-lab.sh) | Monte, vérifie, joue le scénario et arrête le laboratoire |
| [`lab/Dockerfile`](lab/Dockerfile) | Image unique avec les outils annoncés et les services simulés |
| [`lab/telecharger-paquets.sh`](lab/telecharger-paquets.sh) | Télécharge hors ligne les paquets qui construisent l’image |
| [`lab/scenario-incident.sh`](lab/scenario-incident.sh) | Boucle d’incident : balayages, session en clair, flot de paquets |
| [`lab/regles-detection.rules`](lab/regles-detection.rules) | Règles Suricata qui produisent le livrable `alertes-suricata.txt` |

## Source

Le syllabus d’origine, extrait de la plateforme et vérifié, est versionné à côté
du cours : [`syllabus-original.txt`](syllabus-original.txt).
