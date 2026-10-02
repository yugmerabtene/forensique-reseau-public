#!/usr/bin/env python3
"""Convertit la typographie du texte courant en français soutenu.

Deux corrections seulement, et toutes deux portent sur le rendu imprimé :

1. l'apostrophe droite `'` devient l'apostrophe typographique `’` ;
2. les guillemets français `« texte »` sont entourés d'espaces insécables.

Ni le code des blocsfers, ni le code en ligne ne sont touchés : une apostrophe
y est une instruction pour le shell, pas une typographie. Le script est
idempotent : le relancer sur un fichier déjà converti ne change rien.
"""

import re
import sys
import pathlib

# Apostrophe entre deux lettres : c'est le cas de l'élision et du possessif,
# donc l'intégralité des apostrophes du texte courant.
APOSTROPHE = re.compile(r"(?<=[A-Za-zÀ-ÖØ-öø-ÿ])'(?=[A-Za-zÀ-ÖØ-öø-ÿ])")

# Espace insécable : la French typography l'exige autour des guillemets.
INSECABLE = " "


def proteger_code(ligne: str, dans_bloc: bool) -> list:
    """Découpe une ligne en zones de code et zones de texte.

    Une zone de code est un bloc fer, ouvert plus haut, ou une portion entre
    accents graves. Le texte situé entre deux portions de code en ligne est
    du texte courant : il doit donc être converti.
    """
    if dans_bloc:
        return [(ligne, True)]
    morceaux, position = [], 0
    for correspondance in re.finditer(r"`[^`]*`", ligne):
        if correspondance.start() > position:
            morceaux.append((ligne[position:correspondance.start()], False))
        morceaux.append((correspondance.group(0), True))
        position = correspondance.end()
    if ligne.count("`") % 2 == 1:
        # Accent grave orphelin : la fin de la ligne est du code non apparié.
        morceaux.append((ligne[position:], True))
    else:
        morceaux.append((ligne[position:], False))
    return morceaux


def convertir(ligne: str, dans_bloc: bool) -> str:
    sortie = []
    for morceau, est_code in proteger_code(ligne, dans_bloc):
        if est_code:
            sortie.append(morceau)
            continue
        converti = APOSTROPHE.sub("’", morceau)
        converti = re.sub(r"«[  ]*", "«" + INSECABLE, converti)
        converti = re.sub(r"[  ]*»", INSECABLE + "»", converti)
        sortie.append(converti)
    return "".join(sortie)


def traiter(contenu: str) -> str:
    lignes, dans_bloc = [], False
    for ligne in contenu.split("\n"):
        if ligne.startswith("```"):
            dans_bloc = not dans_bloc
            lignes.append(ligne)
            continue
        lignes.append(convertir(ligne, dans_bloc))
    return "\n".join(lignes)


def main(argv):
    if len(argv) < 2:
        print("usage : check-typographie.py fichier.md [...]")
        return 2
    for chemin in argv[1:]:
        fichier = pathlib.Path(chemin)
        avant = fichier.read_text(encoding="utf-8")
        apres = traiter(avant)
        if avant == apres:
            print(f"{chemin} : deja conforme")
            continue
        fichier.write_text(apres, encoding="utf-8")
        difference = sum(1 for a, b in zip(avant.split("\n"), apres.split("\n"))
                         if a != b)
        print(f"{chemin} : {difference} ligne(s) corrigee(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
