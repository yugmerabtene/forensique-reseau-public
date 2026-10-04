#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Rend les schémas Mermaid d'un support et les incorporate au PDF.

Pandoc ne sait pas rendre Mermaid : il recopie le code source dans le document,
et LaTeX massacre au passage les flèches `-->` en `{-}{-}{-}`. Ce script rend
donc chaque schéma en PDF vectoriel, puis produit une copie du support où chaque
bloc ```mermaid est remplacé par une inclusion d'image. C'est cette copie que
la chaîne d'export convertit ensuite.

La lisibilité du texte est une exigence : le rendu passe par la configuration
partagée, qui produit des éléments SVG `<text>` réels, exploitables par
cairosvg. Un `<foreignObject>` ne serait pas rendu, et le texte disparaîtrait.

Usage :
    python3 .opencode/scripts/rendre-schema.py <support.md> <répertoire-sortie>

Affiche sur la sortie standard le chemin de la copie pré-traitée.
"""

import os
import re
import subprocess
import sys
import tempfile

RACINE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONFIG = os.path.join(RACINE, ".opencode", "diagrammes", "mermaid-config.json")

# Bloc LaTeX produit à la place du schéma. graphicx est chargé par le modèle de
# mise en page ; le paquet float ne l'est pas, on évite donc l'environnement
# flottant et l'option [H]. keepaspectratio protège la lisibilité : un schéma
# plus haut que large est réduit, jamais déformé.
GABARIT = """```{=latex}
\\begin{center}
\\includegraphics[width=\\linewidth,height=0.82\\textheight,keepaspectratio]{%s}
\\end{center}
```"""


def echec(message):
    sys.stderr.write("rendre-schema : %s\n" % message)
    sys.exit(1)


def rendre_un(source, repertoire, index):
    """Rend un schéma en PDF vectoriel et renvoie son chemin."""
    avec_pptr = os.path.join(repertoire, "puppeteer.json")
    with open(avec_pptr, "w", encoding="utf-8") as f:
        f.write('{"args":["--no-sandbox","--disable-setuid-sandbox",'
                '"--disable-dev-shm-usage"]}')

    base = os.path.join(repertoire, "fig-%02d" % index)
    source_mmd = base + ".mmd"
    sortie_svg = base + ".svg"
    sortie_pdf = base + ".pdf"

    with open(source_mmd, "w", encoding="utf-8") as f:
        f.write(source)

    proc = subprocess.run(
        ["mmdc", "-i", source_mmd, "-o", sortie_svg, "-p", avec_pptr, "-c", CONFIG],
        capture_output=True, text=True, timeout=300,
    )
    if proc.returncode != 0 or not os.path.exists(sortie_svg):
        detail = (proc.stderr or proc.stdout).strip().splitlines()
        echec("schéma %d : rendu impossible (%s)"
              % (index, detail[-1][:160] if detail else "sortie absente"))

    with open(sortie_svg, encoding="utf-8") as f:
        svg = f.read()
    if "foreignObject" in svg:
        echec("schéma %d : le rendu contient des <foreignObject>, le texte ne "
              "serait pas visible. Vérifiez %s." % (index, CONFIG))

    try:
        import cairosvg
    except ImportError:
        echec("le module cairosvg est absent : impossible de convertir le SVG en PDF")
    cairosvg.svg2pdf(url=sortie_svg, write_to=sortie_pdf)

    os.unlink(source_mmd)
    os.unlink(sortie_svg)
    return sortie_pdf


def principal(support, sortie):
    if not os.path.exists(CONFIG):
        echec("configuration de rendu absente : %s" % CONFIG)

    with open(support, encoding="utf-8") as f:
        texte = f.read()

    blocs = re.findall(r"```mermaid\n(.*?)```", texte, re.S)
    if not blocs:
        # Aucun schéma : la copie est le support lui-même, sans traitement.
        print(os.path.abspath(support))
        return 0

    if not os.path.isdir(sortie):
        os.makedirs(sortie, exist_ok=True)

    resultat = texte
    for index, source in reversed(list(enumerate(blocs, 1))):
        pdf = rendre_un(source, sortie, index)
        # On remplace la dernière occurrence, pour que la numérotation suive
        # l'ordre du document et non celui du remplacement.
        position = resultat.rfind("```mermaid\n" + source + "```")
        if position < 0:
            echec("schéma %d : bloc introuvable au moment du remplacement" % index)
        debut = position
        fin = debut + len("```mermaid\n" + source + "```")
        resultat = resultat[:debut] + (GABARIT % pdf) + resultat[fin:]

    copie = os.path.join(
        sortie, os.path.basename(support).replace(".md", "-schemas.md")
    )
    with open(copie, "w", encoding="utf-8") as f:
        f.write(resultat)
    print(os.path.abspath(copie))
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.stderr.write("Usage : rendre-schema.py <support.md> <répertoire-sortie>\n")
        sys.exit(2)
    sys.exit(principal(sys.argv[1], sys.argv[2]))