#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Contrôle de lisibilité des schémas du cours.

Un schéma illisible est un défaut bloquant : le lecteur perd le sens de la
figure, et le texte rogné dans un cadre ne se remarque pas à la relecture. Ce
contrôle rend chaque schéma avec la configuration partagée, puis vérifie que
le texte est visible en entier et que la figure tient sur une page A4.

FaitRendering: mmdc, avec la configuration .opencode/diagrammes/mermaid-config.json.
Sans la configuration partagée, Mermaid produit des <foreignObject>, que ni
pandoc, ni LaTeX, ni les convertisseurs SVG vers PDF ne savent rendre.

Usage :
    python3 .opencode/scripts/check-schema.py jour-1.md jour-2.md jour-3.md

Code retour 0 si tout est conforme, 1 sinon.
"""

import json
import os
import re
import subprocess
import sys
import tempfile

RACINE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONFIG = os.path.join(RACINE, ".opencode", "diagrammes", "mermaid-config.json")

# Page A4, marges de 2 cm : 460 pt utiles en largeur, 700 pt utiles en hauteur.
PAGE_LARGEUR = 460.0
PAGE_HAUTEUR = 700.0
POLICE_MERMAID = 15.0

# Un libellé plus long est rendu sur une seule ligne, ce qui élargit le schéma.
LIGNE_MAX = 40

# En dessous de cette taille, le texte d'un schéma n'est plus lisible à l'impression.
POLICE_MIN = 5.5

RENVOI_MODELES = ("Ce que le schéma ne montre pas",)


def schemams(sources):
    """Renvoie la liste des blocs mermaid : (fichier, index, source)."""
    trouvés = []
    for chemin in sources:
        with open(chemin, encoding="utf-8") as f:
            texte = f.read()
        for index, bloc in enumerate(
            re.findall(r"```mermaid\n(.*?)```", texte, re.S), 1
        ):
            trouvés.append((chemin, index, bloc))
    return trouvés


def libelles(source):
    """Renvoie les libellés d'un schéma : nœuds, sous-graphes et arêtes."""
    trouves = re.findall(r'\["([^"]*)"\]|\["([^"]*)"\]|\|"([^"]*)"\|', source)
    if not trouves:
        trouves = re.findall(r'\["([^"]*)"\]', source)
    return [x for groupe in trouves for x in groupe if x]


def normaliser(texte):
    """Minuscules, sans ponctuation : « cadre-enquete.md » devient
    « cadreenquetemd ». Le rendu et la source sont ainsi comparables malgré
    les coupures de ligne et les découpages d'accentuation de Mermaid."""
    return re.sub(r"[^a-z0-9à-ÿ]", "", texte.lower())


def rendre(source, pptr, chemin_sortie):
    """Rend un schéma et renvoie (svg ou None, liste d'erreurs)."""
    erreurs = []
    with tempfile.NamedTemporaryFile(
        "w", suffix=".mmd", encoding="utf-8", delete=False
    ) as f:
        f.write(source)
        entree = f.name
    try:
        proc = subprocess.run(
            [
                "mmdc",
                "-i", entree,
                "-o", chemin_sortie,
                "-p", pptr,
                "-c", CONFIG,
            ],
            capture_output=True,
            text=True,
            timeout=180,
        )
        if proc.returncode != 0:
            erreurs.append(
                "rendu impossible ("
                + (proc.stderr or proc.stdout).strip().splitlines()[-1:][0][:160]
                + ")"
            )
            return None, erreurs
        with open(chemin_sortie, encoding="utf-8") as f:
            return f.read(), erreurs
    except FileNotFoundError:
        erreurs.append("mmdc est absent : le rendu ne peut pas être contrôlé")
        return None, erreurs
    except subprocess.TimeoutExpired:
        erreurs.append("rendu trop long")
        return None, erreurs
    finally:
        os.unlink(entree)


def controler(sources):
    anomalies = []

    if not os.path.exists(CONFIG):
        print("Configuration partagée absente : %s" % CONFIG)
        return 1

    with open(CONFIG, encoding="utf-8") as f:
        config = json.load(f)
    if config.get("htmlLabels") is not False:
        anomalies.append(
            "%s : htmlLabels doit valoir false, sinon le rendu produit des "
            "<foreignObject> illisibles dans le PDF" % CONFIG
        )

    blocs = schemams(sources)
    if not blocs:
        anomalies.append("aucun schéma Mermaid trouvé : un cours sans schéma est incomplet")

    if not mmdc_disponible():
        anomalies.append("mmdc est absent : le contrôle de lisibilité est impossible")
        blocs = []

    workdir = tempfile.mkdtemp(prefix="check-schema-")
    pptr = os.path.join(workdir, "puppeteer.json")
    with open(pptr, "w", encoding="utf-8") as f:
        json.dump(
            {
                "args": [
                    "--no-sandbox",
                    "--disable-setuid-sandbox",
                    "--disable-dev-shm-usage",
                ]
            },
            f,
        )

    for chemin, index, source in blocs:
        nom = "%s : schéma %d" % (os.path.basename(chemin), index)
        sortie = os.path.join(workdir, "%s-%d.svg" % (os.path.basename(chemin), index))
        svg, erreurs = rendre(source, pptr, sortie)
        for e in erreurs:
            anomalies.append("%s : %s" % (nom, e))
        if svg is None:
            continue

        # 1. Aucun <foreignObject> : le texte doit être en SVG <text> réel.
        if "foreignObject" in svg:
            anomalies.append(
                "%s : le rendu contient des <foreignObject>, le texte ne "
                "sera pas visible dans le PDF" % nom
            )

        # 2. Aucun libellé tronqué. Mermaid découpe un mot pour l'accentuation
        #    (« Méthodologi » puis « e ») et coupe au trait d'union, donc la
        #    comparaison se fait sur le texte normalisé, sans séparateur.
        rendus = []
        for chunk in re.split(r'<g class="(?:label|cluster)[^"]*"', svg)[1:]:
            rendus.append(
                normaliser(
                    "".join(
                        re.sub(r"<[^>]+>", "", t)
                        for t in re.findall(r"<tspan[^>]*>(.*?)</tspan>", chunk, re.S)
                    )
                )
            )
        blob = " ".join(rendus)
        for libelle in libelles(source):
            attendu = normaliser(libelle.replace("<br/>", ""))
            if attendu and attendu not in blob:
                anomalies.append(
                    "%s : le libellé « %s » n'apparaît pas en entier dans le "
                    "rendu, le texte est tronqué" % (nom, libelle.replace("<br/>", " ")[:60])
                )

        # 3. Une ligne de libellé ne doit pas dépasser 40 caractères.
        for libelle in libelles(source):
            for ligne in libelle.split("<br/>"):
                if len(ligne.strip()) > LIGNE_MAX:
                    anomalies.append(
                        "%s : ligne de libellé de %d caractères, maximum %d : "
                        "« %s »" % (nom, len(ligne.strip()), LIGNE_MAX, ligne.strip()[:60])
                    )

        # 4. Le schéma doit tenir sur une page A4 sans réduire la police.
        boite = re.search(r'viewBox="0 0 ([0-9.]+) ([0-9.]+)"', svg)
        if boite:
            largeur, hauteur = float(boite.group(1)), float(boite.group(2))
            if largeur > 0 and hauteur > 0:
                police = POLICE_MERMAID * min(
                    PAGE_LARGEUR / largeur, PAGE_HAUTEUR / hauteur
                )
                if police < POLICE_MIN:
                    anomalies.append(
                        "%s : trop large pour la page, %.0f x %.0f pixels, "
                        "police ramenée à %.1f pixels (minimum %.1f). Changer "
                        "l'orientation du schéma ou réduire le nombre de "
                        "colonnes."
                        % (nom, largeur, hauteur, police, POLICE_MIN)
                    )

    # 5. Légendes numérotées et continues, renvois et limites déclarées.
    for chemin in sources:
        with open(chemin, encoding="utf-8") as f:
            texte = f.read()
        numeros = [int(n) for n in re.findall(r"\*\*Fig (\d+) [—-]", texte)]
        attendus = list(range(1, len(numeros) + 1))
        if numeros != attendus:
            anomalies.append(
                "%s : numérotation des figures discontinue ou doublonnée : %s"
                % (os.path.basename(chemin), numeros)
            )
        n_blocs = len(re.findall(r"```mermaid\n", texte))
        if n_blocs and len(numeros) != n_blocs:
            anomalies.append(
                "%s : %d schémas mais %d légendes numérotées"
                % (os.path.basename(chemin), n_blocs, len(numeros))
            )
        for modele in RENVOI_MODELES:
            if n_blocs and texte.count(modele) < n_blocs:
                anomalies.append(
                    "%s : chaque schéma doit porter « %s » (trouvé %d fois pour "
                    "%d schémas)"
                    % (os.path.basename(chemin), modele, texte.count(modele), n_blocs)
                )
        for numero in numeros:
            if len(re.findall(r"[Ff]ig(?:ure)?\.? %d\b" % numero, texte)) < 2:
                anomalies.append(
                    "%s : la figure %d n'est citée dans aucune étape"
                    % (os.path.basename(chemin), numero)
                )

    if anomalies:
        print("check-schema : %d anomalie(s)" % len(anomalies))
        for a in anomalies:
            print("  - %s" % a)
        return 1

    print(
        "check-schema : %d schémas conformes, texte visible, figure tenant sur "
        "une page A4" % len(blocs)
    )
    return 0


def mmdc_disponible():
    """Indique si mmdc est appelable, sans importer shutil pour rien."""
    for dossier in os.environ.get("PATH", "").split(os.pathsep):
        if dossier and os.access(os.path.join(dossier, "mmdc"), os.X_OK):
            return True
    return False


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage : check-schema.py jour-1.md jour-2.md jour-3.md")
        sys.exit(2)
    sys.exit(controler(sys.argv[1:]))