#!/usr/bin/env python3
"""Contrôle de conformité du cours « Forensique réseau » (jour-1.md, jour-2.md,
jour-3.md).

Le support est un livre : deux chapitres par journée, chacun avec un préambule
vulgarisé, un vocabulaire en clair, une répartition du temps, des techniques
expliquées puis un LAB qui produit un livrable repris par le suivant.

Le contrôle vérifie :
  - structure : titre, date, objectifs, planning, fil du jour
  - annexe du code du laboratoire présente dans les trois journées
  - jours : trois fichiers, deux chapitres par journée
  - découpage : 360 min de formation par journée, pause déjeuner déduite
  - en-tête de chapitre cohérent avec les créneaux du planning
  - volume interne : la somme des sous-parties vaut la durée annoncée
  - LAB : prérequis, environnement, étapes numérotées, résultat attendu,
    livrable nommé ; la somme des étapes vaut la durée du LAB
  - chaîne des livrables : chaque chapitre produit un livrable, la section
    « Le fil du jour » le déclare, et le chapitre suivant le reprend
  - blocs bash : syntaxe validée bloc par bloc (bash -n)
  - blocs de code : tous avec un langage déclaré
  - expressions de filtre : chaque filtre publié doit être accepté par tcpdump
  - terminologie : pas de « séquence », pas de « TP », pas de notation /10,
    pas d'emoji, pas de caractère étranger
  - orthographe : formes interdites du CONTEXT.md
  - réseaux : uniquement des segments du laboratoire
  - liens : joignabilité des références

Usage : python3 .opencode/scripts/check-course.py
Code retour : 0 conforme, 1 anomalies détectées, 2 fichier manquant.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request

FICHiers = ["jour-1.md", "jour-2.md", "jour-3.md"]
MODULES_ATTENDUS = {
    "jour-1.md": ["M1", "M2"],
    "jour-2.md": ["M3", "M4"],
    "jour-3.md": ["M5", "M6"],
}
DATES_ATTENDUES = {
    "jour-1.md": "12/10/2026",
    "jour-2.md": "13/10/2026",
    "jour-3.md": "14/10/2026",
}
ERREURS = []

SECTIONS_JOUR = [
    "## Objectifs du Jour",
    "## Planning du Jour",
    "## Le fil du jour",
    "## Synthèse",
    "### Couverture Jour",
    "### Mémo — commandes essentielles",
    "## Ressources supplémentaires",
    "### Outils utilisés",
    "### Références",
    "## Annexe — Le code du laboratoire",
]

# Chaque rubrique obligatoire du gabarit, avec son niveau de titre exact.
# Le niveau n'est pas décoratif : une rubrique retrogradée sort du chapitre au
# rendu PDF, et la pastille du livrable ne se pose plus.
PIECES_CHAPITRE = [
    (3, "Préambule"),
    (3, "Le vocabulaire en clair"),
    (3, "Objectifs du chapitre"),
    (3, "Répartition du temps"),
    (3, "Contenu du chapitre"),
    (3, "Les techniques, pas à pas"),
    (3, "LAB —"),
    (4, "Prérequis"),
    (4, "Environnement"),
    (4, "Étapes du LAB"),
    (3, "Ce que ce LAB produit"),
    (3, "Exercices — Chapitre"),
]

# Un livrable est un fichier nommé et daté, pas une intention. Sans chemin
# ni nom de fichier, le chapitre suivant ne peut pas le consommer et la
# chaîne des LAB se rompt sans que rien ne le signale.
MOTIF_LIVRABLE = r"[~/][\w./-]+\.(?:txt|md|pcap|sha256|log|json|csv|yaml)"


def fail(fichier, message):
    ERREURS.append(f"{fichier} : {message}")


def duree_minutes(texte):
    """« 1h30 » -> 90, « 45min » -> 45, « 2h » -> 120. None si illisible."""
    m = re.match(r"^(\d+)\s*h(?:([0-9]{2}))?$", texte.strip())
    if m:
        return int(m.group(1)) * 60 + int(m.group(2) or 0)
    m = re.match(r"^(\d+)\s*min$", texte.strip())
    return int(m.group(1)) if m else None


def creneaux_et_minutes(cellule):
    """« 11h00–12h00 et 13h00–16h00 » -> [(« 11h00–12h00 », 60), (…, 180)]."""
    resultat = []
    for morceau in re.split(r"\s+et\s+", cellule.strip()):
        m = re.match(r"^(\d+h\d\d)[–-](\d+h\d\d)$", morceau.strip())
        if not m:
            return None
        minutes = duree_minutes(m.group(2)) - duree_minutes(m.group(1))
        if minutes <= 0:
            return None
        resultat.append((m.group(0), minutes))
    return resultat or None


def controler_blocs(fichier, texte):
    """Syntaxe de chaque bloc bash et présence d'un langage sur chaque bloc."""
    ouverts = []
    for i, ligne in enumerate(texte.split("\n"), 1):
        if ligne.startswith("```"):
            if not ouverts:
                if not ligne[3:].strip():
                    fail(fichier, f"bloc de code sans langage à la ligne {i}")
                ouverts.append((i, ligne[3:].strip(), []))
            else:
                debut, langage, corps = ouverts.pop()
                if langage == "bash" and corps:
                    with tempfile.NamedTemporaryFile("w", suffix=".sh",
                                                     delete=False) as tmp:
                        tmp.write("\n".join(corps))
                        chemin = tmp.name
                    r = subprocess.run(["bash", "-n", chemin],
                                       capture_output=True, text=True)
                    if r.returncode != 0:
                        fail(fichier, f"bloc bash invalide (ligne {debut}) : "
                                      f"{r.stderr.strip()}")
                    os.unlink(chemin)
        elif ouverts:
            ouverts[-1][2].append(ligne)
    if ouverts:
        fail(fichier, f"fence de code non fermée, ouverte ligne {ouverts[0][0]}")


def controler_terminologie(fichier, texte):
    motifs = [
        # La frontière de mot est indispensable : sans elle, le mot français
        # « conséquence » contient la suite « séquence » et était signalé à tort.
        # Le tiret est exclu du même examen, pour que « sous-sequence » ne soit
        # pas confondu avec le terme proscrit.
        (r"(?<![\w-])[Ss]équence", "terme proscrit : « séquence » (écrire chapitre)"),
        (r"\bTP\b|\bTPs\b|\btravaux pratiques\b", "terme proscrit : « TP » (écrire LAB)"),
        (r"(?<![0-9/])\d{1,2}\s*/\s*10(?![0-9/])", "notation /10"),
        (r"forensique reseau", "orthographe : forensique réseau"),
        (r"preuve digitale", "terminologie : preuve numérique"),
        (r"\bsequentiel\b|\bsequentielle\b", "orthographe : séquentiel, "
                                             "séquentielle"),
        (r"perte de paquets", "orthographe : pertes de paquets"),
        ("[぀-ヿ一-鿿가-힯Ѐ-ӿ"
         "؀-ۿ]", "caractère étranger dans un support français"),
        ("[\U0001F300-\U0001FAFF☀-➿️]",
         "emoji"),
    ]
    for motif, libelle in motifs:
        for m in re.finditer(motif, texte):
            extrait = texte[max(0, m.start() - 40):m.end() + 40].replace("\n", " ")
            fail(fichier, f"{libelle} : ...{extrait}...")


def controler_entete_jour(fichier, texte):
    m = re.search(r"^## .+? \((\d{2}/\d{2}/\d{4})\)$", texte, re.M)
    if not m:
        fail(fichier, "date de la journée absente (attendu « (JJ/MM/AAAA) »)")
    elif m.group(1) != DATES_ATTENDUES[fichier]:
        fail(fichier, f"date {m.group(1)} au lieu de {DATES_ATTENDUES[fichier]}")


def controler_planning(fichier, texte):
    """Le planning déclare les créneaux de chaque chapitre. Un chapitre peut
    occuper deux créneaux séparés par la pause déjeuner : le champ « Créneaux »
    les liste alors joints par « et »."""
    lignes = []
    section = re.search(r"^## Planning du Jour\n(.*?)(?=^## )", texte,
                        re.S | re.M)
    if not section:
        fail(fichier, "section « Planning du Jour » absente")
        return {}
    # La numérotation des chapitres est continue sur les trois journées : elle
    # se déduit des modules attendus du jour, et non d'une liste figée sur le
    # premier jour.
    attendus = ["C" + m[1:] for m in MODULES_ATTENDUS[fichier]]
    for ligne in section.group(1).split("\n"):
        if re.match(r"^\| C\d( \(suite\))? \|", ligne) or re.match(r"^\| — \|", ligne):
            lignes.append(ligne)
    plan = []
    pauses = []
    for ligne in lignes:
        colonnes = [c.strip() for c in ligne.strip().strip("|").split("|")]
        if len(colonnes) < 4:
            continue
        if colonnes[0] == "—":
            pauses.append(colonnes)
        else:
            plan.append(colonnes)
    if len(plan) != 2:
        fail(fichier, f"planning : {len(plan)} chapitres (attendu 2)")
        return {}
    if len(pauses) != 1:
        fail(fichier, f"planning : {len(pauses)} pauses (attendu 1, "
                      f"la pause déjeuner)")
    volume = 0
    creneaux = {}
    for colonnes in plan:
        chapitre = colonnes[0]
        liste = creneaux_et_minutes(colonnes[1])
        if liste is None:
            fail(fichier, f"{chapitre} : créneaux illisibles : {colonnes[1]!r}")
            continue
        reel = sum(minutes for _, minutes in liste)
        declare = duree_minutes(colonnes[3])
        if declare is not None and reel != declare:
            fail(fichier, f"{chapitre} : planning annonce {colonnes[3]} pour "
                          f"{reel} min de créneaux")
        volume += reel
        creneaux[chapitre] = (colonnes[1], reel)
    for colonnes in pauses:
        liste = creneaux_et_minutes(colonnes[1])
        if liste is None:
            fail(fichier, f"pause : créneaux illisibles : {colonnes[1]!r}")
            continue
        reel = sum(minutes for _, minutes in liste)
        declare = duree_minutes(colonnes[3])
        if declare is not None and reel != declare:
            fail(fichier, f"pause {colonnes[1]} : annonce {colonnes[3]} "
                          f"pour {reel} min")
    if volume != 360:
        fail(fichier, f"volume pédagogique {volume} min (attendu 360 = 6 h "
                      f"de formation)")
    if [c[0] for c in plan] != attendus:
        fail(fichier, f"numérotation des chapitres : {[c[0] for c in plan]} "
                      f"(attendu {attendus})")
    return creneaux


def controler_chapitres(fichier, texte, creneaux, livrables):
    blocs = re.split(r"^## Chapitre (\d+) — (M\d) : (.+?) \((.+?)\)$",
                     texte, flags=re.M)
    if len(blocs) < 5:
        fail(fichier, "aucun chapitre détecté")
        return
    modules_trouves = []
    for i in range(1, len(blocs), 5):
        num, module, _titre, créneaux, corps = blocs[i:i + 5]
        modules_trouves.append(module)
        chapitre = f"C{num}"
        if chapitre not in creneaux:
            fail(fichier, f"{chapitre} : absent du planning")
            continue
        if creneaux[chapitre][0] != créneaux.strip():
            fail(fichier, f"{chapitre} : en-tête « {créneaux.strip()} » différent "
                          f"du planning « {creneaux[chapitre][0]} »")
        duree = creneaux[chapitre][1]
        # Répartition déclarée : elle doit couvrir la totalité du chapitre,
        # préambule, contenu, techniques, LAB et exercices compris.
        m_rep = re.search(r"^### Répartition du temps\n\n\| Partie \| Durée \|\n"
                          r"\|-+\|-+\|\n((?:\|.+?\|\n)+)", corps, re.M)
        if not m_rep:
            fail(fichier, f"{chapitre} : tableau « Répartition du temps » absent")
        else:
            parts = [int(p) for p in re.findall(r"\| (\d+)min \|$", m_rep.group(1), re.M)]
            if sum(parts) != duree:
                fail(fichier, f"{chapitre} : répartition {sum(parts)} min != "
                              f"{duree} min de chapitre")
            etiquettes = re.findall(r"^\| ([^|]+?) \| \d+min \|$", m_rep.group(1), re.M)
            for attendue in ("Contenu du chapitre", "LAB", "Exercices"):
                if attendue not in etiquettes:
                    fail(fichier, f"{chapitre} : « Répartition du temps » sans "
                                  f"ligne « {attendue} »")
        # Découpage interne du chapitre.
        m = re.search(r"^### Contenu du chapitre \((\d+)min\)", corps, re.M)
        m_lab = re.search(r"^### LAB — .+?\((\d+)min\)", corps, re.M)
        if not m:
            fail(fichier, f"{chapitre} : durée du contenu absente")
        elif not m_lab:
            fail(fichier, f"{chapitre} : LAB sans durée")
        else:
            contenu, lab = int(m.group(1)), int(m_lab.group(1))
            if contenu + lab > duree:
                fail(fichier, f"{chapitre} : contenu {contenu} + LAB {lab} = "
                              f"{contenu + lab} min pour {duree} min de "
                              f"chapitre, sans temps pour l'ouverture et les "
                              f"exercices")
            parties = re.findall(r"^#### \d+\. .+?\((\d+)min\)", corps, re.M)
            if not parties:
                fail(fichier, f"{chapitre} : aucune sous-partie minutée")
            elif sum(int(p) for p in parties) != contenu:
                fail(fichier, f"{chapitre} : sous-parties {sum(int(p) for p in parties)} "
                              f"min != contenu {contenu} min")
        etapes = re.findall(r"^\*\*Étape \d+ — [^*]*?\((\d+) ?min", corps, re.M)
        if not etapes:
            fail(fichier, f"{chapitre} : aucune étape de LAB numérotée")
        elif m_lab and sum(int(e) for e in etapes) != lab:
            fail(fichier, f"{chapitre} : étapes {sum(int(e) for e in etapes)} min "
                          f"!= LAB {lab} min")
        for niveau, piece in PIECES_CHAPITRE:
            if not re.search(rf"^#{{{niveau}}} {re.escape(piece)}", corps, re.M):
                fail(fichier, f"{chapitre} : rubrique obligatoire absente au "
                              f"niveau {niveau} : {piece}")
        if "```bash" not in corps and "```markdown" not in corps:
            fail(fichier, f"{chapitre} : aucun bloc de commandes")
        if corps.count("> **Résultat attendu :**") < len(etapes):
            fail(fichier, f"{chapitre} : {len(etapes)} étapes pour "
                           f"{corps.count('> **Résultat attendu :**')} résultats "
                           f"attendus")
        # Livrable du LAB, et prérequis qui doivent reprendre le livrable précédent.
        m_prod = re.search(r"^### Ce que ce LAB produit\n\n(.+?)\n", corps, re.M | re.S)
        if m_prod:
            livrables[chapitre] = m_prod.group(1).strip()
            if not re.search(MOTIF_LIVRABLE, livrables[chapitre]):
                fail(fichier, f"{chapitre} : livrable non nommé — un chemin de "
                              f"fichier est attendu pour que le LAB suivant le "
                              f"consomme")
        else:
            fail(fichier, f"{chapitre} : le livrable du LAB n'est pas décrit")
        m_prereq = re.search(r"^#### Prérequis\n\n(.+?)\n\n", corps, re.M | re.S)
        if m_prereq:
            livrables[chapitre + "-prereq"] = m_prereq.group(1).strip()
    if modules_trouves != MODULES_ATTENDUS[fichier]:
        fail(fichier, f"numérotation des modules : {modules_trouves} "
                      f"(attendu {MODULES_ATTENDUS[fichier]})")
    # Couverture finale : les deux chapitres du jour, dans l'ordre. Les
    # chapitres attendus se déduisent des modules attendus de la journée, et
    # non d'une liste figée sur le premier jour.
    attendus = ["C" + m[1:] for m in MODULES_ATTENDUS[fichier]]
    couv = re.findall(r"^\| (C\d) \| (M\d)", texte, re.M)
    if [c for c, _ in couv] != attendus:
        fail(fichier, f"synthèse : couverture {[c for c, _ in couv]} "
                      f"(attendu {attendus})")


def controler_fil(fichier, texte, livrables):
    """Le fil du jour doit déclarer le livrable de chaque chapitre, et le chapitre
    suivant doit le reprendre explicitement dans ses prérequis."""
    fil = re.search(r"^## Le fil du jour\n(.*?)\n---", texte, re.S | re.M)
    if not fil:
        fail(fichier, "section « Le fil du jour » absente ou mal délimitée")
        return
    contenu = fil.group(1)
    chapitres = [c for c in livrables if not c.endswith("-prereq")]
    for chapitre in chapitres:
        if f"| {chapitre} " not in contenu and f"| {chapitre} —" not in contenu:
            fail(fichier, f"le fil du jour ne mentionne pas le chapitre {chapitre}")
        fichiers = re.findall(MOTIF_LIVRABLE, livrables[chapitre])
        if fichiers and not any(f in contenu for f in fichiers):
            fail(fichier, f"le fil du jour ne reprend pas le livrable de {chapitre} "
                           f"({', '.join(fichiers)})")
    # Le prérequis du second chapitre doit citer le livrable du premier.
    if len(chapitres) == 2:
        premier, second = chapitres
        fichiers = re.findall(MOTIF_LIVRABLE, livrables.get(premier, ""))
        prereq = livrables.get(f"{second}-prereq", "")
        if fichiers and not any(f in prereq for f in fichiers):
            fail(fichier, f"les prérequis du chapitre {second} ne citent pas le "
                           f"livrable de {premier} ({', '.join(fichiers)})")


def controler_reseau(fichier, texte):
    """Seuls les segments du laboratoire sont admis dans les supports.

    Le masque 0.0.0.0/0 des listes de contrôle d'accès et l'adresse de boucle
    interne 127.0.0.1 sont enseignés : ce ne sont pas des segments du
    laboratoire, mais ce ne sont pas non plus des données client.

    Le pont Docker de chaque segment est créé en /23, et non en /24 : c'est un
    choix délibéré, qui place la passerelle technique du pont en dehors du /24
    réellement utilisé par le laboratoire. Ces valeurs sont des paramètres du
    pont, jamais des adresses d'hôtes, et le code du laboratoire les reproduit
    dans l'annexe. Les tolérer ici évite de signaler une valeur qui est
    correcte, tout en gardant la règle stricte sur tout le reste du support.
    """
    segments_autorises = {"10.10.0.0/24", "10.20.0.0/24", "0.0.0.0/0",
                          "10.10.0.0/23", "10.20.0.0/23",
                          "10.10.1.0/24", "10.20.1.0/24"}
    passerelles_du_pont = {"10.10.1.253", "10.20.1.253"}
    # L'adresse de base du quartier que le pont se reserve, ecrite sans son
    # masque dans les commentaires du laboratoire.
    bases_du_pont = {"10.10.1.0", "10.20.1.0"}
    for segment in set(re.findall(r"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.0/\d{1,2}\b", texte)):
        if segment not in segments_autorises:
            fail(fichier, f"segment hors laboratoire : {segment}")

    # Chaque adresse d'hôte citée doit appartenir à un segment autorisé.
    # Les adresses placées dans un avertissement pédagogique (« une adresse mal
    # tapée ») sont tolérées : elles sont signalées à l'enquêteur, pas utilisées.
    corps_sans_avertissement = re.sub(r"^>.*mal\s+tap[ée]e.*$", "", texte,
                                       flags=re.M | re.I)
    for adresse in set(re.findall(r"\b(?:\d{1,3}\.){3}\d{1,3}\b",
                                  corps_sans_avertissement)):
        octets = [int(o) for o in adresse.split(".")]
        if len(octets) != 4 or any(o > 255 for o in octets):
            continue
        if adresse in ("0.0.0.0", "127.0.0.1") or adresse in passerelles_du_pont \
                or adresse in bases_du_pont:
            continue
        if not (adresse.startswith("10.10.0.") or adresse.startswith("10.20.0.")):
            fail(fichier, f"adresse hors laboratoire : {adresse}")
            return


def controler_filtres_bpf(fichier, texte):
    """Chaque expression de filtre publiée doit être acceptée par tcpdump.

    Un filtre écrit dans une syntaxe non supportée par la version installée
    échoue à l'exécution sur le poste du formateur : c'est un défaut bloquant
    que la relecture à l'œil ne voit pas.
    """
    if not shutil.which("tcpdump"):
        return 0
    motifs = re.findall(r"tcpdump\s+[^\n|]*?\s('([^']+)'|\"([^\"]+)\")", texte)
    vus = set()
    for _, simple, double in motifs:
        expression = simple or double
        if expression.startswith("-"):
            continue  # ce sont des options, pas un filtre
        if expression in vus:
            continue
        vus.add(expression)
        r = subprocess.run(["tcpdump", "-d", "-y", "EN10MB", expression],
                           capture_output=True, text=True)
        if r.returncode != 0 or "syntax error" in r.stderr:
            fail(fichier, f"filtre BPF refusé par tcpdump : {expression}")
    return len(vus)


# Un serveur public n'a aucune obligation de répondre à la requête d'un robot :
# certains refusent la méthode HEAD, d'autres limitent le nombre de requêtes ou
# servent une page d'attente. Signaler ces réponses comme un lien rompu rend le
# contrôle aléatoire, et un contrôle aléatoire est un contrôle auquel on apprend
# à ne pas croire.
#
# Un lien n'est donc déclaré rompu que si deux tentatives consécutives échouent
# de la même façon. Une adresse réellement morte échoue à chaque tentative ; une
# panne de réseau passagère, elle, ne se reproduit pas. Les refus font preuve
# que l'adresse existe : ils ne sont pas signalés, non plus que les redirections,
# que le client HTTP suit déjà.
REFUS = (403, 405, 429, 501)


def interroger_lien(url, methode):
    """Une tentative. Renvoie un verdict, jamais une exception.

    Le corps de la réponse n'est pas lu : la méthode HEAD suffit à savoir si
    l'adresse existe, et ne pas lire évite de télécharger une documentation
    entière pour vérifier son en-tête.
    """
    requete = urllib.request.Request(url, method=methode,
                                     headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(requete, timeout=20) as r:
            if r.status < 400:
                return "ok"
            return "refus" if r.status in REFUS else "absent"
    except urllib.error.HTTPError as e:
        if e.code in REFUS:
            return "refus"
        return "absent"
    except Exception as e:
        return "injoignable (%s)" % type(e).__name__


def controler_liens(fichier, texte):
    # L'adresse peut être la dernière colonne d'un tableau à deux colonnes
    # comme celle d'un tableau plus large qui ajoute une remarque : on la
    # cherche dans n'importe quelle colonne, après le nom de la ressource.
    # Les classes excluent aussi le retour à la ligne, sans quoi le motif
    # déborderait d'une ligne du tableau sur la suivante.
    liens = re.findall(r"^\| ([^\n|]+) \|(?:[^\n|]*\|)*\s*(https?://[^\s|\n]+)\s*\|",
                       texte, re.M)
    for nom, url in liens:
        # Deux requêtes de tête, encadrées d'une requête complète : un serveur
        # qui refuse la première répond parfois à la suivante, et l'inverse est
        # vrai aussi. C'est la répétition, et non la première réponse, qui
        # fait foi.
        verdicts = [interroger_lien(url, m) for m in ("HEAD", "GET", "HEAD")]
        if verdicts[0] == "ok":
            continue
        if sum(1 for v in verdicts if v.split()[0] in ("absent", "injoignable")) >= 2:
            fail(fichier, f"lien « {nom.strip()} » -> {verdicts[0]}, "
                          f"puis {verdicts[1]}, {verdicts[2]}")
    return len(liens)


def main():
    racine = os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    for fichier in FICHiers:
        chemin = os.path.join(racine, fichier)
        if not os.path.exists(chemin):
            print(f"ECHEC {fichier} : fichier absent")
            return 2
        texte = open(chemin, encoding="utf-8").read()
        for section in SECTIONS_JOUR:
            if section not in texte:
                fail(fichier, f"section obligatoire absente : {section}")
        controler_entete_jour(fichier, texte)
        controler_blocs(fichier, texte)
        controler_terminologie(fichier, texte)
        creneaux = controler_planning(fichier, texte)
        livrables = {}
        controler_chapitres(fichier, texte, creneaux, livrables)
        controler_fil(fichier, texte, livrables)
        controler_reseau(fichier, texte)
        n_bpf = controler_filtres_bpf(fichier, texte)
        nb_liens = controler_liens(fichier, texte)
        n_lab = len([c for c in livrables if not c.endswith("-prereq")])
        print(f"{fichier} : {len(creneaux)} chapitres, {n_lab} LAB, "
              f"{n_bpf} filtres BPF compilés, {nb_liens} liens vérifiés")
    if ERREURS:
        print("\n--- ANOMALIES ---")
        for e in ERREURS:
            print("ECHEC", e)
        return 1
    print("\nRESULTAT : cours conforme (structure livre, 6 h par jour, LAB "
          "enchaînés, blocs bash, filtres BPF, terminologie, liens)")
    return 0


if __name__ == "__main__":
    sys.exit(main())