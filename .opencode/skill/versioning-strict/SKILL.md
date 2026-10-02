---
name: versioning-strict
description: Use when committing, pushing or modifying files in the forensics-reseaux course repo (jour-1.md, jour-2.md, jour-3.md, syllabus-original.txt, .opencode/**) — enforces strict atomic versioning with a mandatory pre-commit secret-scan gate, and forbids any leak of external credentials (API tokens, passwords, private keys, connection secrets). Lab data, IP addresses and course content are explicitly NOT restricted.
---

# Versioning strict et zéro fuite de credentials

Ce skill est la source de vérité opérationnelle pour toute action de versionnement
de ce dépôt. Il complète `.opencode/agent/orchestrateur.md` (qui doit le charger)
et `.opencode/CONTEXT.md` (qui doit le rappeler). En cas de divergence, la règle la
plus stricte l'emporte.

## Périmètre de la protection : credentials externes uniquement

Sont protégés, et eux seuls :

- Tokens d'API et tokens d'accès (GitHub `ghp_`, GitLab `glpat-`, Slack `xox*`,
  Google)
- Mots de passe, phrases de passe
- Clés privées, certificats, keystores
- Secrets de connexion, community strings SNMP réelles, identifiants
- Chaînes de connexion contenant une credential en clair

Ne sont **pas** restreints : le contenu du cours, les segments et adresses de
laboratoire (`10.10.0.0/24`, `10.20.0.0/24`, `10.10.0.20`, `10.20.0.10`…), les
ports de démonstration (22, 23, 80, 443, 445, 514, 9200), les mots de passe de
laboratoire documentés dans le tableau d'environnement d'un LAB, les noms d'outils
(`tcpdump`, `tshark`, `suricata`, `zeek`…), les journaux simulés produits par le
laboratoire, les valeurs de configuration publiques.

## Autonomie : jamais de demande d'autorisation

Le mandat de l'utilisateur est l'exécution sans validation. Ce skill ne
s'autorise jamais à revenir en arrière pour demander une permission :

- Aucune confirmation avant `bash`, `edit`, install, commit, push, lecture.
- Aucun usage de l'outil `question` pour valider un choix technique : applique
  l'option la plus raisonnable et indique-la dans la réponse finale.
- Une tâche confiée est exécutée de bout en bout, tests et push compris, avant tout
  compte rendu.
- Seules exceptions : la règle de versioning strict, la règle de zéro fuite de
  credentials et la confidentialité du dépôt privé. En cas de conflit, la sécurité
  l'emporte et le signalement est explicite.

## Terminologie imposée : LAB, chapitre, jamais TP ni séquence

- Écrire **LAB** (laboratoire). Le terme « TP » est proscrit dans tout contenu
  généré ou modifié par les agents : supports, tableaux, titres, exercices,
  messages de commit, fichiers de suivi, réponses utilisateur.
- Écrire **chapitre**. Le terme « séquence » est proscrit partout, y compris dans les
  intitulés de colonnes de tableaux et les messages de commit. L'unité de cours est
  le chapitre.
- Le support est un livre : chaque chapitre s'ouvre par un préambule qui vulgarise le
  sujet, contient un tableau de vocabulaire en clair, un tableau de répartition du
  temps, expose les techniques pas à pas, puis propose un LAB.
- Chaque LAB déclare ses prérequis, son environnement, ses étapes minutées et le
  livrable qu'il produit pour le LAB suivant.

## Gate obligatoire avant chaque commit

Aucun commit sans avoir exécuté les quatre étapes, dans cet ordre :

```bash
git status                        # 1. lister exactement ce qui est modifié
git diff --cached --stat          # 2. confirmer que seuls les fichiers voulus sont indexés
.opencode/scripts/check-secrets.sh # 3. scan anti-fuite — code retour 1 = commit INTERDIT
git commit -m "Prefixe: description courte"
```

- `check-secrets.sh` sans argument scanne le **diff indexé**. Avec des chemins en
  argument, il scanne ces fichiers ou répertoires.
- Codes de retour : `0` propre, `1` fuite détectée (blocage), `2` usage invalide.
- Un code retour `1` impose de remplacer la valeur par un gabarit, puis de rejouer
  le contrôle. Aucun contournement, aucun `--no-verify`, aucun
  `export SKIP_SECRET_SCAN=1`.

## Règles de commit

| Règle | Application |
|-------|-------------|
| Atomicité | un commit = une unité de travail terminée (module, LAB, relecture, correction, configuration) |
| Fréquence | commit dès qu'un fichier est validé ; au plus 3 fichiers modifiés avant commit |
| Message | français, `Prefixe: description courte` |
| Prefixes | `Generation`, `Relecture`, `Correction`, `Tests`, `Tracking`, `Versioning`, `Systeme` |
| Traçabilité | `.opencode/tracking.json` mis à jour dans le **même** commit que la modification |
| Push | après chaque série de commits significatifs, sur le remote **privé** |
| Arbre propre | `git status` propre au démarrage ; sinon finir la tâche en cours d'abord |

## Interdits absolus

- `git push --force`, `git push --force-with-lease`
- `git commit --amend` sur un commit déjà poussé
- Réécriture d'historique
- `git checkout .`, `git reset --hard`, `git clean -fd` pour se débarrasser d'un
  travail non commité : on commite ou on stase, jamais on détruit
- `git add -A` / `git add .` sans avoir lu `git status` (risque d'indexer un secret)
- Basculer la visibilité du remote vers publique, retirer le remote, ajouter un dépôt
  public comme remote secondaire
- Commiter des captures ou des journaux de production réelle : seules les preuves
  simulées du laboratoire sont admises, et `.gitignore` exclut `/captures/` et
  `/journaux/` par précaution

## Écriture de valeurs sensibles dans les supports

Toujours un gabarit, jamais une valeur :

```bash
# Correct
export GH_TOKEN="<VOTRE_TOKEN_GITHUB>"
ssh-copy-id -i <CLE_PUBLIE_SRV> enquêteur@10.10.0.20

# opencode
"apiKey": "{env:MY_API_KEY}"
```

Splunk exige un compte et une clé de licence : n'écrire que
`<VOTRE_CLE_LICENCE_SPLUNK>` et `<VOTRE_COMPTE_SPLUNK>`.

En cas de détection fortuite d'une credential dans un fichier, une sortie de
commande ou l'historique git :

1. Ne pas la recopier, ne pas l'afficher dans la réponse.
2. La remplacer immédiatement par un gabarit.
3. Commiter `Correction: fuite de credential retiree du depot`.
4. Avertir l'utilisateur que le remote est privé et qu'une rotation du secret est
   nécessaire côté client.

## Trace d'exécution

Le skill journalise la référence du commit dans `.opencode/tracking.json`
(`current_task.last_commit`) dans le même commit que la modification du cours.

## Contrôle de qualité du cours (complément du gate anti-fuite)

Le gate anti-fuite protège les credentials ; il ne vérifie pas la qualité
rédactionnelle. Avant de déclarer un support prêt, exécuter :

```bash
python3 .opencode/scripts/check-course.py                    # code retour 0 attendu
python3 .opencode/scripts/check-texte.py jour-1.md jour-2.md jour-3.md
python3 .opencode/scripts/check-pdf.py jour-1.md jour-2.md jour-3.md
python3 .opencode/scripts/check-typographie.py jour-1.md jour-2.md jour-3.md
```

`check-typographie.py` corrige au lieu de signaler : le relancer jusqu'à ce qu'il
annonce « déjà conforme ». Les trois autres doivent renvoyer 0.

Le contrôle échoue si le support contient le mot « séquence » ou « TP », si un
chapitre manque de préambule, de vocabulaire en clair, de répartition du temps, de
techniques ou de LAB, si la durée d'un chapitre ne correspond pas à son contenu, si
le tableau de répartition du temps ne somme pas au volume du chapitre, si un bloc bash
est syntaxiquement invalide, si une expression de filtre est refusée par `tcpdump`,
si une adresse hors laboratoire est citée, si un anglicisme de confort ou un
caractère étranger est présent, ou si une référence n'est plus joignable. Un code
retour `1` bloque la validation du support, au même titre qu'une fuite bloque le
commit.