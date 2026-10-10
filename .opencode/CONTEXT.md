# Contexte Projet — Forensique réseau

## Résumé du Projet

Formation de 3 jours en forensique réseau pour la **DGFIP**, dispensée en présentiel
à **Paris** par le prestataire **Ascent**. Le syllabus source, extrait de la
plateforme Eluv, est versionné dans `syllabus-original.txt`.

**Client :** DGFIP
**Prestataire :** Ascent
**Lieu :** Présentiel à Paris
**Durée :** 3 jours (12, 13 et 14 octobre 2026), 6 h par jour, soit 18 h
**Horaires :** 9 h – 12 h et 13 h – 16 h, chaque jour
**Prérequis :** Connaissances de base des réseaux (TCP/IP, routage, commutation) ;
expérience des outils de capture et d'analyse réseau (Wireshark, tcpdump)
**Public ciblé :** Investigateurs en informatique légale, analystes en
cybersécurité, administrateurs réseaux, responsables de la sécurité des systèmes
d'information

**Modèle LLM requis :** opencode/big-pickle (uniquement)

---

## Objectifs pédagogiques du syllabus

Les quatre objectifs du client, repris tels quels, sont le contrat de la formation.

1. Appréhender les bases de l'analyse forensique appliquée aux réseaux.
2. Identifier et collecter les données pertinentes sur les réseaux pour l'analyse
   forensique.
3. Utiliser des outils spécialisés pour analyser le trafic réseau et détecter des
   traces d'intrusions.
4. Savoir répondre à des incidents de sécurité réseau et effectuer une analyse
   détaillée des événements.

---

## Programme (syllabus) et découpage retenu

Le client laisse explicitement le contenu de chaque chapitre et leur ordre libres :
seuls les chapitres listés doivent être traités. Le découpage ci-dessous est un
choix du formateur, il ne rajoute ni ne retire de matière.

| Module | Titre du syllabus | Durée réf. | Contenu imposé par le client | Chapitre | Créneau |
|--------|-------------------|-----------|-------------------------------|----------|---------|
| M1 | Introduction à la forensique réseau | 2 h | Concepts de collecte, préservation et analyse ; types de données (paquets, flux, journaux, configurations) ; différences réseaux local et étendu | C1 | J1 9 h 00 – 11 h 00 |
| M2 | Capture et collecte des données réseau | 4 h | Collecte avec Wireshark et tcpdump ; éléments critiques d'un paquet (adresses, ports, protocoles) | C2 | J1 11 h 00 – 12 h 00 et 13 h 00 – 16 h 00 |
| M3 | Analyse des paquets et détection des anomalies | 3 h | Flux légitimes contre anomalies ; scans, attaques par déni de service, intrusions | C3 | J2 9 h 00 – 12 h 00 |
| M4 | Utilisation des journaux et des outils d'analyse réseau | 3 h | Journaux de pare-feu, routeurs et serveurs ; Zeek, Suricata, Splunk | C4 | J2 13 h 00 – 16 h 00 |
| M5 | Réponse aux incidents de sécurité réseau | 3 h | Isolation, collecte des preuves, suivi des actions ; retracer l'attaque et son vecteur | C5 | J3 9 h 00 – 12 h 00 |
| M6 | Rédaction du rapport d'enquête réseau | 3 h | Méthodologie, analyse, résultats, recommandations ; traçabilité et conformité légale | C6 | J3 13 h 00 – 16 h 00 |

**Total référencé : 18 h pour 18 h de formation.** Le volume du syllabus tombe
exactement sur les trois journées : aucune compression, aucun ajout de module.
C'est la différence majeure avec le projet d'audit réseau, où 21 h de référence
devaient tenir dans 12 h.

La journée 1 porte les deux premiers chapitres, dont le second est le plus long du
cours : il occupe la fin de la matinée et l'après-midi complet, la pause déjeuner
étant le seul intervalle non couvert.

---

## Progression du Projet

| Jour | Fichier | Horaires | Chapitres et modules | Statut |
|------|---------|----------|-----------------------|--------|
| Jour 1 — lundi 12/10/2026 | `jour-1.md` | 9 h – 16 h | C1 (M1, 2 h) et C2 (M2, 4 h) | À produire |
| Jour 2 — mardi 13/10/2026 | `jour-2.md` | 9 h – 16 h | C3 (M3, 3 h) et C4 (M4, 3 h) | À produire |
| Jour 3 — mercredi 14/10/2026 | `jour-3.md` | 9 h – 16 h | C5 (M5, 3 h) et C6 (M6, 3 h) | À produire |

**Tâche en cours :** le système agentique est en place ; les trois supports restent
à écrire. Voir `.opencode/tracking.json` pour l'état réel.

**Règle transverse :** le versioning est régulier et obligatoire — voir la section
« Versioning strict du cours ». Chaque action significative sur le cours se
termine par un commit et un push.

---

## Chaîne des livrables — le fil des trois jours

La formation est une chaîne continue : le livrable d'un chapitre est la matière
première du suivant, et le rapport du jour 3 repose sur les cinq livrables
produits les deux premiers jours. Cette chaîne est la structure même du cours.

| Jour | Chapitre | Livrable produit | Consommé par |
|------|----------|------------------|--------------|
| J1 | C1 — M1 | `~/enquete/cadre-enquete.md` : périmètre, types de données, chaîne de conservation | C2, quicapture sur ce périmètre |
| J1 | C2 — M2 | `~/enquete/capture-reference.pcap` : capture de référence horodatée | C3 et C4, qui la relisent |
| J1 | C2 — M2 | `~/enquete/inventaire-hotes.txt` : hôtes, ports et protocoles observés | C3, base du repérage des anomalies |
| J2 | C3 — M3 | `~/enquete/anomalies.md` : anomalies constatées et filtre qui les prouve | C4 et C5 |
| J2 | C4 — M4 | `~/enquete/alertes-suricata.txt` : alertes du moteur de détection, recoupées avec C3 | C5, qui en tire la chronologie |
| J3 | C5 — M5 | `~/enquete/chronologie-incident.md` : chronologie, vecteur d'intrusion, périmètre affecté | C6 |
| J3 | C6 — M6 | `~/enquete/rapport-enquete.md` : rapport d'enquête complet | restitution de fin de formation |

Un livrable produit par une commande est réellement produit par cette commande. Un
livrable rédigé est saisi au clavier par l'apprenant, et le support doit le dire.
Un livrable annoncé sans commande ni saisie est un défaut bloquant : le jour
suivant le consomme et ne le trouve pas.

---

## Environnement de laboratoire

Un seul jeu de réseaux sert les trois jours, ce qui permet à l'apprenant de
reconnaître les mêmes machines d'un chapitre à l'autre.

| Élément | Valeur |
|---------|--------|
| Réseau du site central | `10.10.0.0/24` |
| Réseau de la filiale | `10.20.0.0/24` |
| Poste de l'enquêteur | `10.10.0.10`, compte ordinaire `enqueteur` |
| Passerelle du site central | `10.10.0.1` |
| Serveur applicatif | `10.10.0.20` — ports 22, 80, 443 ouverts |
| Serveur de fichiers | `10.10.0.30` — port 23 en clair et 445, le port 23 est l'anomalie à expliquer |
| Collecteur de journaux | `10.10.0.50` — syslog, Suricata, Zeek |
| Passerelle de la filiale | `10.20.0.1` |
| Poste compromis | `10.20.0.10` — origine de l'incident |
| Serveur de la filiale | `10.20.0.20` — ports 22 et 80 ouverts |

Les deux segments sont distincts et non chevauchants, et appartiennent à l'espace
d'adressage privé. Aucune donnée réelle du client DGFIP ne figure dans un support :
un réseau dEssai suffit à rendre chaque notion démontrable.

**Outils annoncés et outillage du laboratoire**

| Outil | Chapitres | Rôle dans le cours | Présence dans l'image |
|-------|-----------|--------------------|-----------------------|
| `tcpdump` | M1, M2, M3 | Capture en ligne de commande, filtres BPF | oui |
| `tshark` | M2, M3 | Analyse d'une capture en ligne de commande | oui |
| `wireshark` | M1, M2, M3 | Analyse visuelle de la capture | oui |
| `nmap` | M2, M3 | Découverte d'hôtes et d'états de ports | oui |
| `iperf3` | M2 | Génération d'un trafic connu pour une capture propre | oui |
| `suricata` | M3, M4 | Moteur de détection, journaux au format JSON | oui |
| `rsyslog` | M4 | Collecte des journaux du pare-feu, du routeur et des serveurs | oui |
| `zeek` | M4 | Analyse de réseau en profondeur, journaux de connexions | non, installation documentée |
| `splunk` | M4 | Centralisation et corrélation des journaux | non, installation documentée |

Zeek et Splunk ne sont pas dans les dépôts de distribution et ne peuvent donc pas
être installés hors ligne. Ils sont traités en **outils optionnels** : le support
annonce leur rôle, donne la procédure d'installation et fournit une repli exécutable
dans l'image — les journaux EVE de Suricata au format JSON — pour qu'aucune étape
ne dépende d'un outil absent. Le support signale toujours la dépendance et la
repli, comme l'impose la règle 4 des règles de détail du cours.

---

## Format des Fichiers Cours — le support est un livre

Le support se lit comme un livre : on explique avant de montrer, on nomme les
mots, puis on met les mains sur le clavier. L'unité de découpage est le
**chapitre**. Chaque chapitre alterne explication et manipulation.

### Vocabulaire imposé

| Terme | Usage |
|-------|-------|
| Chapitre | Unité de cours correspondant à un module du syllabus (le mot « séquence » est proscrit) |
| Module | Référence du syllabus (M1 à M6), portée dans le titre du chapitre |
| LAB | Laboratoire pratique (le mot « TP » est proscrit) |
| Préambule | Texte d'ouverture qui vulgarise le problème avant la technique |
| Vocabulaire en clair | Tableau qui traduit chaque terme technique en langage courant |
| techniques, pas à pas | Partie qui explique chaque technique avant de donner la commande |
| Livrable | Fichier nommé, produit par un chapitre et repris par le suivant |

### Découpage horaire d'une journée

Chaque journée comporte **deux chapitres** et une pause déjeuner d'une heure. Les
horaires sont ceux du client : 9 h – 12 h et 13 h – 16 h.

Un chapitre dont le volume est de 3 h occupe un bloc entier, le matin ou l'après-midi.
Un chapitre de 2 h laisse une heure à un autre chapitre ou à une ouverture. Le
chapitre de 4 h du jour 1 occupe la fin de la matinée et l'après-midi complet : la
pause déjeuner est le seul intervalle qu'il ne couvre pas, et le support le dit
plutôt que de présenter une durée continue de 11 h à 16 h.

### Gabarit exact d'un jour

```markdown
# Forensique réseau — JOUR X

## [Titre du jour] (JJ/MM/AAAA)

---

## Objectifs du Jour

## Planning du Jour

| Chapitre | Créneaux | Module et thème | Volume |
|----------|----------|-----------------|--------|
| C1 | 9h00–11h00 | M1 — Introduction à la forensique réseau | 2h |
| C2 | 11h00–12h00 et 13h00–16h00 | M2 — Capture et collecte des données réseau | 4h |
| — | 12h00–13h00 | Pause déjeuner | 1h |

Volume pédagogique : 6 h de formation (2 h et 4 h), 1 h de pause déjeuner.

## Le fil du jour

[Paragraphe et tableau : ce que chaque chapitre produit et ce que le suivant consomme.]

---

## Chapitre N — MN : Titre (créneaux)

### Préambule — [ce dont parle ce chapitre, en clair]

[2 à 4 paragraphes. Une analogie concrète, le problème réel, l'enjeu. Jamais de
définition technique avant d'avoir posé le problème.]

### Le vocabulaire en clair

| Terme | En clair | Dans ce chapitre |
|-------|----------|------------------|
| [terme] | [explication en français courant] | [où on le rencontre] |

### Objectifs du chapitre

### Répartition du temps

| Partie | Durée |
|--------|-------|
| Préambule, vocabulaire et objectifs | Xmin |
| Contenu du chapitre | Ymin |
| Techniques, pas à pas | Zmin |
| LAB | Wmin |
| Exercices | Vmin |

### Contenu du chapitre (Ymin)

#### 1. Sous-partie (Xmin)

[tableaux, commandes, explications]

### Les techniques, pas à pas

[Pour chaque technique : ce qu'elle fait, la commande, ce que la sortie prouve, ce
qu'elle ne prouve pas.]

### LAB — Titre (Wmin)

#### Prérequis

[Ce qui doit déjà fonctionner, et ce que le LAB précédent a produit.]

#### Environnement

| Élément | Valeur |
|---------|--------|
| Poste de l'enquêteur | `enqueteur`@10.10.0.10 |
| Réseau du site central | 10.10.0.0/24 |

#### Étapes du LAB

**Étape N — Titre (Xmin)**

[Explication en une phrase, puis le bloc de commandes, puis le résultat attendu.]

### Ce que ce LAB produit

[Livrable nommé, chemin complet, repris par le LAB suivant. Cette rubrique est de
niveau 3 : elle porte la pastille verte du livrable dans le PDF, et une rubrique
rétrogradée d'un niveau sortirait du chapitre au rendu.]

### Exercices — Chapitre N

---

## Synthèse

### Couverture Jour X

| Chapitre | Module | Thème |
|----------|--------|-------|

### Mémo — commandes essentielles

## Ressources supplémentaires

### Outils utilisés

### Références

## Annexe — Le code du laboratoire

[Code complet de chaque fichier de `lab/`, reproduit verbatim, precede de son rôle
et suivi d'une lecture commentée. Jour 1 : `telecharger-paquets.sh`, `Dockerfile`,
`construire-lab.sh`. Jour 2 : `regles-detection.rules`, `scenario-incident.sh`.
Jour 3 : renvoi motive vers les deux premieres annexes, pour ne pas dupliquer le
code. Le code reproduit ne doit jamais etre corrige dans le support : il est
compare octet pour octet au fichier reel.]
```

---

## Règles de Format

### Système agentique — ce qui est en place et comment le vérifier

Le projet est conduit par un agent principal, `orchestrator`, et trois sous-agents.
Ce sont des agents OpenCode réels : ils sont déclarés une fois pour toutes, ils ne
sont pas décrits seulement dans ce fichier.

| Élément | Emplacement | Rôle |
|---------|-------------|------|
| Agent principal | `opencode.json`, clé `agent.orchestrator` | Pilote la production, délègue, consolide |
| Agent par défaut | `opencode.json`, clé `default_agent` | Force le démarrage sur `orchestrator` |
| Rédacteur | `.opencode/agent/course-writer.md` | Rédaction des chapitres, modules, LAB, exercices |
| Validateur | `.opencode/agent/code-tester.md` | Validation des commandes, filtres et laboratoire |
| Relecteur | `.opencode/agent/proofreader.md` | Relecture finale et contrôle de conformité |
| Développeur web | `.opencode/agent/web-developer.md` | Génère presentation.html (slide deck horizontal, monofichier, schémas intégrés) |
| Contexte | `.opencode/CONTEXT.md`, clé `instructions` | Chargé dans chaque session |
| Modèle imposé | `opencode/big-pickle` | Le seul modèle autorisé, sur les quatre agents |

**Redémarrage obligatoire après toute création ou renommage d'agent.** OpenCode
établit sa liste d'agents au démarrage de la session. Un agent ajouté pendant une
session n'apparaît pas dans l'outil `task` de cette session : la configuration est
correcte sur le disque, mais la session en cours l'ignore. C'est la cause la plus
fréquente du constat « le système agentique n'est pas en place », et ce constat est
alors faux. Il faut quitter opencode puis le relancer.

**Racine du projet : le répertoire de lancement doit être la racine.** OpenCode lit
`opencode.json` et `.opencode/` à partir du répertoire depuis lequel il est lancé,
et ne va pas chercher la configuration dans un sous-répertoire. La racine de ce
projet est donc `/home/yug/Documents/forensics`, là où opencode est lancé, et non un
sous-répertoire du projet. Cette règle vaut pour tout déplacement : un `opencode.json`
placé ailleurs rend le système agentique invisible sans produire la moindre erreur.

**Vérification, à faire avant de conclure à un défaut.** Trois commandes, à lancer
depuis `/home/yug/Documents/forensics` :

```bash
opencode agent list        # les quatre agents doivent apparaître
opencode debug config      # default_agent doit valoir orchestrator
opencode run "quel est ton nom d'agent et quels sous-agents sont disponibles ?"
```

La troisième est la seule décisive : elle interroge une session neuve, dans les
mêmes conditions que l'utilisateur. Un agent annoncé dans un fichier mais absent de
cette réponse désigne une configuration non chargée, pas un agent fonctionnel.

---

## Règles de Format

### Autonomie d'exécution

- L'utilisateur donne le mandat d'exécution sans validation : **aucune demande
  d'autorisation**, quel que soit l'agent ou le skill.
- Permissions en `allow` pour tous les outils (voir `opencode.json`, au niveau
  principal et pour l'agent `orchestrateur`).
- Tâche confiée = tâche exécutée de bout en bout : action, tests, gate anti-fuite,
  commits, push, puis compte rendu final unique.
- L'autonomie ne contourne pas le versioning strict, ni la zéro fuite de
  credentials, ni la confidentialité du dépôt privé. En cas de conflit, la règle de
  sécurité l'emporte et le signalement est explicite.

### Langue et qualité du français (RÈGLE OBLIGATOIRE)

- **Langue :** français uniquement, du début à la fin, y compris dans les titres,
  les commentaires de code, les messages de commit et les réponses utilisateur.
- **Français soutenu :** phrases courtes, sujet explicite, verbes d'action. Écrire
  « on mesure », « la commande renvoie », « le constat est établi » — jamais de
  télégraphie, de jargon non expliqué ni de calque de l'anglais.
- **Accents obligatoires :** aucun mot sans accent n'est toléré dans le texte
  courant. Un mot sans accent est un défaut à corriger avant commit.
- **Un terme technique, deux lectures :** le terme anglais ou l'abréviation est
  conservé (PCAP, BPF, EVE, IDS, SIEM, DDoS, RTT, SNR, TLS), mais il est traduit
  au moins une fois en français courant dans le tableau « Le vocabulaire en clair »
  du chapitre, puis il est employé tel quel ensuite. Le lecteur ne doit jamais
  rester devant un mot non expliqué.
- **Anglicismes de confort à bannir :** « scanner » quand « sonder » convient,
  « check » quand « vérifier » convient, « setup » quand « configuration »
  convient, « log » quand « journal » convient, « output » quand « sortie »
  convient, « input » quand « entrée » convient, « dashboard », « tooling ». Le nom
  propre de l'outil reste bien sûr autorisé (`tcpdump`, `tshark`, `suricata`).
- **Guillemets français :** « texte », avec espaces insécables. Apostrophe
  typographique ’. Tirets cadratins — pour les incises.
- **Pas d'emoji** dans les titres ou le contenu.
- **Pas de notation** (pas de /10, pas de « X points »).
- **Aucune phrase inachevée**, aucune liste sans point, aucun mot coupé en fin de
  ligne.
- **Sortie d'outil jamais recopiée telle quelle :** elle est reformulée en français et
  réduite aux lignes significatives. Les blocs de code contiennent la commande et,
  quand elle est nécessaire à la démonstration, la sortie brute.
- **Contrôle automatique :** `python3 .opencode/scripts/check-course.py` vérifie la
  structure, le français et les liens, et renvoie 1 si une anomalie subsiste.

### Schémas — obligation et normes de lisibilité (RÈGLE OBLIGATOIRE)

Un cours sans schéma est un cours incomplet. Tout support contient des schémas, et
chaque LAB en contient au moins un.

**Pourquoi cette règle existe.** Un schéma dont le texte est tronqué, illisible ou
absent du PDF ne sert plus le lecteur. La lisibilité du texte d'un schéma est
donc un critère de qualité, au même titre que l'exactitude d'une commande. Un schéma
illisible est un défaut bloquant, pas un détail de mise en forme.

**Configuration imposée.** Tout rendu passe par le fichier de configuration partagé
`.opencode/diagrammes/mermaid-config.json`, qui impose `htmlLabels: false`. Ce
réglage est obligatoire et non négociable : il produit des éléments SVG `<text>`
réels au lieu de `<foreignObject>`, que ni pandoc, ni LaTeX, ni les convertisseurs
SVG vers PDF ne savent rendre. Un rendu produit sans ce fichier est un rendu non
conforme.

**Normes de lisibilité, contrôlées automatiquement.**

1. **Le texte est visible en entier.** Aucun libellé ne doit être tronqué, coupé au
   milieu d'un mot ni rogné par la largeur du cadre.
2. **Une ligne de libellé ne dépasse pas 40 caractères.** Au-delà, le schéma s'élargit,
   il est réduit à la largeur de la page à l'export, et le texte devient illisible.
   Les libellés longs sont donc coupés explicitement avec `<br/>`, à un coupure de mot
   et à un retour à la ligne par idée.
3. **Le sens de lecture est annoncé** dans la phrase qui introduit le schéma, afin que
   le lecteur sache par où commencer.
4. **Chaque schéma porte une légende numérotée** `**Fig N — Titre.**`, et la
   numérotation `Fig N` est continue et sans doublon dans tout le support.
5. **Chaque schéma est référencé au moins une fois** dans les étapes qu'il éclaire.
   Un schéma que personne ne cite est un schéma décoratif.
6. **Chaque schéma déclare ses limites** par une phrase `Ce que le schéma ne montre
   pas : …`. Le lecteur doit savoir ce que la lecture du schéma ne prouve pas.

**Vérification obligatoire.** Le rendu de chaque schéma est contrôlé par
`python3 .opencode/scripts/check-schema.py jour-1.md jour-2.md jour-3.md`, qui rend
les schémas avec `mmdc` et la configuration partagée, puis signale tout libellé trop
long, tout `<foreignObject>`, toute numérotation cassée, toute légende absente, tout
renvoi manquant et toute limite non déclarée. Le rendu dans le PDF livré est vérifié
par `check-pdf.py`. Ce contrôle s'ajoute aux quatre contrôleurs existants.

### Règles de détail du cours (RÈGLE OBLIGATOIRE)

Le cours s'adresse à des investigateurs qui doivent être autonomes le jour de
l'enquête. Le support ne laisse jamais une affirmation sans preuve.

1. **Rien n'est affirmé sans être démontrable** — chaque concept est soit défini par
   une commande, soit illustré par un tableau, soit prouvé par un résultat de LAB.
   Pas d'affirmation décorative.
2. **Chaque technique est expliquée avant d'être exécutée** : ce qu'elle mesure, la
   commande exacte, ce que la sortie prouve, ce qu'elle ne prouve pas.
3. **Chaque commande est testée avant d'être publiée** : syntaxe vérifiée, sortie
   attendue confrontée à la sortie réelle, dépendance signalée si l'outil manque.
4. **Chaque LAB est autonome et reproductible** : environnement complet (adresses,
   ports, outils, versions), prérequis explicites, étapes numérotées et minutées,
   résultat attendu, dépannage en cas d'échec.
5. **Les LAB s'enchaînent** : un LAB produit un livrable nommé, le LAB suivant le
   consomme explicitement. La section « Le fil du jour » de chaque journée rend
   cette chaîne visible, et le « Ce que ce LAB produit » nomme le chemin complet du
   fichier.
6. **Le détail est au bon niveau** : assez fin pour être exécuté sans improvisation,
   jamais au point de noyer le lecteur. On explique le pourquoi avant le comment.
7. **Aucune valeur magique** : toute adresse, tout port, tout seuil utilisé dans un
   exemple est justifié ou provient du tableau d'environnement du LAB.
8. **Vulgarisation avant technique** : le préambule pose le problème en langage
   courant avec une analogie concrète ; le contenu technique vient ensuite.
9. **Un chapitre = un module du syllabus** : aucune partie du programme n'est
   omise, aucune partie n'est traitée hors de son module.
10. **Repères de temps systématiques** : chaque chapitre annonce ses durées, chaque
    étape de LAB est minutée, la somme correspond à la durée réelle. Le tableau
    « Répartition du temps » est obligatoire et sa somme vaut le volume du
    chapitre.
11. **Notion propre à la forensique :** le cours enseigne l'horodatage, la
    conservation et la traçabilité des preuves. Un chapitre qui manipule des preuves
    énonce la règle de conservation qu'il applique et l'inscrit dans le livrable.
12. **Aucun apprenant ne peut être perdu.** Chaque LAB commence par rappeler
    comment démarrer le laboratoire : construction ou redémarrage du conteneur,
    commande de vérification qui prouve que le poste répond, et emplacement du
    répertoire de travail. Un LAB qui suppose un laboratoire déjà démarré sans le
    dire est un défaut bloquant. Le lecteur ne doit jamais devoir deviner une
    commande manquante, ni se demander pourquoi une capture est vide.

### Conventions

- **Numérotation des modules :** continue — M1 et M2 pour le jour 1, M3 et M4 pour
  le jour 2, M5 et M6 pour le jour 3.
- **Unité de cours :** le **chapitre**. Le mot « séquence » est proscrit partout —
  cours, règles, suivi, messages de commit.
- **Terminologie :** le projet parle de **LAB** (laboratoire). Le terme « TP » est
  proscrit dans tout contenu rédigé ou généré par les agents, y compris les messages
  de commit et le suivi.
- **Préambule obligatoire :** chaque chapitre s'ouvre par un préambule qui explique le
  sujet en langage courant avant toute notion technique.
- **Vocabulaire en clair obligatoire :** chaque chapitre contient un tableau qui
  traduit ses termes techniques.
- **LAB :** toujours avec environnement détaillé, prérequis, étapes numérotées,
  résultat attendu et livrable nommé.
- **Code blocks :** toujours avec langage déclaré (bash, json, text, markdown).
- **Tableaux :** alignés, sans emoji d'en-tête, nombre de colonnes identique sur
  toutes les lignes.

### Obligation de test

**IMPORTANT :** toujours tester le code et les LAB avant de les valider.

1. **Code Bash et Python :** vérifier la syntaxe avec `bash -n` et `python3 -m
   py_compile`, puis l'exécution réelle quand l'environnement le permet.
2. **Commandes :** s'assurer qu'elles sont fonctionnelles ; une option inexistante,
   un filtre refusé par `tcpdump` ou une plage de ports incohérente est un défaut
   bloquant.
3. **Environnement :** valider les adresses, les ports et les configurations ; le
   tableau d'environnement doit permettre de recréer le LAB.
4. **Résultats :** confronter le « résultat attendu » à la sortie réelle de la
   commande. Un résultat attendu inatteignable est un défaut bloquant.
5. **Dépendances :** vérifier que les outils existent et sont accessibles ; sinon
   indiquer l'installation et la repli executable.
6. **Fil du cours :** vérifier que le livrable annoncé par un LAB est bien repris par
   le suivant, et qu'il est produit par une commande ou une saisie explicitement
   décrite.
7. **Contrôle global :** exécuter les quatre contrôleurs avant de déclarer une
   journée terminée :

   ```bash
   python3 .opencode/scripts/check-course.py    # structure, durées, français, liens, filtres BPF
   python3 .opencode/scripts/check-texte.py jour-1.md jour-2.md jour-3.md
   python3 .opencode/scripts/check-pdf.py jour-1.md jour-2.md jour-3.md
   python3 .opencode/scripts/check-typographie.py jour-1.md jour-2.md jour-3.md
   python3 .opencode/scripts/check-schema.py jour-1.md jour-2.md jour-3.md
   ```

   `check-typographie.py` corrige au lieu de signaler : le relancer jusqu'à ce
   qu'il annonce « déjà conforme ». Les quatre autres doivent renvoyer 0. Le
   contrôle des schémas est celui qui garantit que le texte d'une figure est
   visible en entier ; il rend réellement chaque schéma, il ne le relit pas.

---

## Versioning strict du cours (RÈGLE OBLIGATOIRE)

Le cours est sous versionnement git continu. **Aucune modification ne doit rester
non commitée en fin d'action.** Règle détaillée dans
`.opencode/skill/versioning-strict/SKILL.md` et
`.opencode/agent/orchestrateur.md` (le skill prime en cas de divergence).

### Gate obligatoire avant chaque commit

```
git status                            # 1. voir exactement ce qui est modifié
git diff --cached --stat              # 2. vérifier que seuls les fichiers voulus sont indexés
.opencode/scripts/check-secrets.sh    # 3. scan anti-fuite — code 1 = commit INTERDIT
git commit -m "Prefixe: description courte"
```

| Règle | Application |
|-------|-------------|
| Atomicité | Un commit = une unité de travail terminée (module, LAB, relecture, correction) — jamais un mélange |
| Fréquence | Un commit par tâche cohérente terminée, sans accumulation (3 fichiers modifiés = commit) |
| Message | Français, format `Prefixe: description courte`, sans emoji |
| Prefixes | `Generation`, `Relecture`, `Correction`, `Tests`, `Tracking`, `Versioning`, `Systeme` |
| Secrets | `.env`, `*.key`, `*.pem`, `*.p12`, `id_rsa`, `.netrc`, `credentials*`, `secrets*` : JAMAIS versionnés |
| Push | Après chaque série de commits significatifs |
| Traçabilité | `tracking.json` mis à jour dans le même commit que la modification |
| Interdits | `--force`, `--force-with-lease`, `--amend` sur commit poussé, réécriture d'historique, `reset --hard` / `clean -fd` pour effacer un travail non commité |

### Zéro fuite de credentials

**Périmètre strict : les credentials externes uniquement** (tokens d'API, tokens
d'accès, mots de passe, clés privées, certificats, secrets de connexion,
identifiants). **Tout le reste est libre** : contenu du cours, données de
laboratoire (`10.10.0.0/24`, `10.20.0.0/24`), adresses et ports de démonstration,
noms d'outils.

1. Jamais de token, mot de passe ou clé privée en clair dans un support, un message
   de commit, le suivi, un journal ou une sortie d'outil.
2. Jamais de lecture de `.env`, `*.pem`, `*.key`, `id_rsa`, `.netrc`,
   `credentials*`, `secrets*` pour en extraire une valeur.
3. Gabarits obligatoires dans les supports : `export GH_TOKEN="<VOTRE_TOKEN_GITHUB>"`,
   `"apiKey": "{env:MY_API_KEY}"`, `password : <A_COMPLETER>`.
4. Contrôle `.opencode/scripts/check-secrets.sh` avant chaque commit ; code retour 1
   = blocage, corriger puis rejouer.
5. Détection fortuite : ne pas recopier, remplacer par un gabarit, committer la
   correction, prévenir l'utilisateur qu'une rotation du secret est nécessaire côté
   client.
6. Client DGFIP : uniquement des réseaux de laboratoire dans les supports, aucune
   donnée sensible réelle.

### Vérification avant relance

```
git status                    # arbre propre attendu
git log --oneline -5          # historique à jour
```

---

### Erreurs courantes à éviter

1. « forensique réseau » ne s'écrit jamais « forensique reseau ».
2. « preuve numérique » ne s'écrit jamais « preuve digitale » sans justification :
   l'expression attendue est « preuve numérique ».
3. « à l'aide de », pas « a l'aide de ».
4. Aucun caractère étranger dans un support en français : le contrôleur le signale,
   mais un caractère copié depuis une autre langue se glisse parfois dans un mot.
5. « TP » → « LAB ».
6. « séquence » → « chapitre ».
7. « attacke », « scan », « log », « output » → « attaque », « balayage », « journal »,
   « sortie ».
8. La date du jour 1 est le **12** octobre 2026, pas le 12 octobre 2025 ; le
   contrôleur ne vérifie pas les dates, la relecture les vérifie.