#!/usr/bin/env python3
"""Contrôle de préparation à l'export PDF des supports de cours.

L'export PDF transforme le Markdown en document paginé. Un tableau dont les
lignes n'ont pas le même nombre de colonnes s'affiche alors avec des colonnes
supplémentaires vides, un bloc de code non fermé avale tout le reste du
document, et un lien interne vers une ancre inexistante devient une page
introuvable. Ce contrôle porte sur ces défauts de structure, que la relecture
à l'œil ne voit pas.

Le texte des blocs de code est exclu de tous les contrôles de texte : un
apostrophe droite y est une instruction pour le shell, pas une faute
typographique.

usage : check-pdf.py fichier.md [...]
code retour : 0 si le support est prêt, 1 sinon.
"""

import re
import sys
import unicodedata
import pathlib

FENCE = "```"
APOSTROPHE = re.compile(r"(?<=[A-Za-zÀ-ÖØ-öø-ÿ])'(?=[A-Za-zÀ-ÖØ-öø-ÿ])")
# Un separateur de colonne est une barre verticale non echappee. La barre
# echappee `\|` appartient au contenu de la cellule, typiquement une
# expression reguliere comme `grep -c '^\|'`, et ne cree aucune colonne.
BARRE = re.compile(r"(?<!\\)\|")


def sans_code(lignes):
    """Marque chaque ligne par son statut : dans un bloc de code ou non.

    Le retour est la liste des (ligne, est_du_texte_courant).
    """
    marque, ouvert = [], False
    for ligne in lignes:
        if ligne.startswith(FENCE):
            marque.append((ligne, False))
            ouvert = not ouvert
        else:
            marque.append((ligne, not ouvert))
    return marque


def controler_fermetures(fichier, lignes, anomalies):
    ouverts, nombre = [], 0
    for numero, ligne in enumerate(lignes, 1):
        if not ligne.startswith(FENCE):
            continue
        if ouverts:
            if not ouverts[-1][1]:
                anomalies.append(f"{fichier} L{numero} : bloc de code ouvert ligne "
                                 f"{ouverts[-1][0]} sans langage")
            ouverts.pop()
        else:
            ouverts.append((numero, ligne[len(FENCE):].strip()))
            nombre += 1
    if ouverts:
        anomalies.append(f"{fichier} L{ouverts[-1][0]} : bloc de code jamais fermé")
    return nombre


def controler_tableaux(fichier, marque, anomalies):
    tableaux, courante = [], []

    def clore():
        if len(courante) >= 2:
            tableaux.append(list(courante))
        courante.clear()

    for numero, (ligne, est_texte) in enumerate(marque, 1):
        if not est_texte or not ligne.lstrip().startswith("|"):
            clore()
            continue
        courante.append((numero, ligne.strip()))
    clore()

    for bloc in tableaux:
        debut, largeurs = bloc[0][0], [len(BARRE.findall(l)) for _, l in bloc]
        reference = largeurs[0]
        if len(set(largeurs)) != 1:
            fautives = [f"L{n} ({c} séparateurs)" for (n, _), c in zip(bloc, largeurs)
                        if c != reference]
            anomalies.append(f"{fichier} L{debut} : tableau à {reference - 1} "
                             f"colonnes, lignes incohérentes : {', '.join(fautives)}")
        if not re.match(r"^\|[\s:|-]+\|[\s:|-]*$", bloc[1][1]):
            anomalies.append(f"{fichier} L{bloc[1][0]} : deuxième ligne de tableau "
                             f"absente ou mal formée, le tableau ne sera pas rendu "
                             f"comme un tableau")
        for numero, ligne in bloc:
            if "||" in ligne.replace("|| ", "||"):
                anomalies.append(f"{fichier} L{numero} : cellule vide, "
                                 f"colonne fantôme au rendu")
    return len(tableaux)


def controler_hierarchie(fichier, marque, anomalies):
    niveaux = [(numero, len(m.group(1)), ligne.strip())
               for numero, (ligne, est_texte) in enumerate(marque, 1)
               if est_texte and (m := re.match(r"^(#{1,6}) ", ligne))]
    for precedent, suivant in zip(niveaux, niveaux[1:]):
        if suivant[1] - precedent[1] > 1:
            anomalies.append(f"{fichier} L{suivant[0]} : saut de hiérarchie, "
                             f"titre de niveau {precedent[1]} puis {suivant[1]} "
                             f"({suivant[2][:50]})")
    return niveaux


def controler_sections(fichier, niveaux, anomalies):
    """Verifie que chaque chapitre contient bien ses rubriques, au bon niveau.

    Une rubrique retrogradee d'un cran, par exemple un preambule passe de
    « ### » a « ## », ne casse pas la syntaxe du document : le controle de
    hierarchie ne voit aucun saut, et le support est converti sans broncher.
    Au rendu, pourtant, cette rubrique sort du chapitre et devient un chapitre
    de niveau egal : la table des matieres affiche un chapitre supplementaire,
    et le lecteur perd la structure du livre.

    On exige donc que chaque chapitre possede, au niveau 3, les rubriques qui
    definissent le gabarit : preambule, vocabulaire, objectifs, repartition du
    temps, contenu, techniques, LAB, livrable et exercices.
    """
    obligatoires = ("Préambule", "Le vocabulaire en clair", "Objectifs du chapitre",
                    "Répartition du temps", "Contenu du chapitre",
                    "Les techniques, pas à pas", "LAB",
                    "Ce que ce LAB produit", "Exercices")

    chapitres = []
    for numero, niveau, ligne in niveaux:
        # controler_hierarchie conserve la ligne entiere, dieses compris : on
        # retire le prefixe pour ne garder que le texte du titre.
        titre = re.sub(r"^#{1,6}\s+", "", ligne).strip()
        if niveau == 2 and re.match(r"^Chapitre\s+\d+", titre):
            chapitres.append([numero, titre, []])
        elif chapitres and niveau == 3:
            chapitres[-1][2].append(titre)

    for numero, titre, sections in chapitres:
        presentes = [s for s in sections
                     if any(s.startswith(o) for o in obligatoires)]
        for nom in obligatoires:
            if not any(s.startswith(nom) for s in presentes):
                anomalies.append(f"{fichier} L{numero} : le chapitre « {titre[:40]} » "
                                 f"n'a pas de rubrique « {nom} » de niveau 3. "
                                 f"Elle est probablement rétrogradée, et sortira "
                                 f"du chapitre au rendu.")


def controler_ancres(fichier, texte, niveaux, anomalies):
    ancres = set()
    for _numero, _niveau, titre in niveaux:
        ancres.add(re.sub(r"[^a-z0-9 \-]", "", titre.lower())
                   .strip().replace(" ", "-"))
    for m in re.finditer(r"\[([^\]]+)\]\(#([^)]+)\)", texte):
        if m.group(2) not in ancres:
            anomalies.append(f"{fichier} : lien interne vers #{m.group(2)} "
                             f"sans titre correspondant")


def controler_texte(fichier, marque, anomalies):
    droites, espaces, tabulations, controles = 0, [], [], []
    for numero, (ligne, est_texte) in enumerate(marque, 1):
        if ligne != ligne.rstrip() and ligne.strip():
            espaces.append(numero)
        if "\t" in ligne:
            tabulations.append(numero)
        for caractere in ligne:
            if unicodedata.category(caractere) in ("Cc", "Cf", "Co", "Cs"):
                controles.append(f"L{numero} {caractere!r}")
        if not est_texte:
            continue
        prose = re.sub(r"`[^`]*`", "", ligne)
        droites += len(APOSTROPHE.findall(prose))
    if espaces:
        anomalies.append(f"{fichier} : espaces en fin de ligne aux lignes "
                         f"{espaces[:6]}")
    if tabulations:
        anomalies.append(f"{fichier} : tabulations aux lignes {tabulations[:6]}")
    if controles:
        anomalies.append(f"{fichier} : caractères de contrôle ou de formatage "
                         f"invisibles : {controles[:5]}")
    if droites:
        anomalies.append(f"{fichier} : {droites} apostrophes droites dans le texte "
                         f"courant, à remplacer par l'apostrophe typographique "
                         f"(voir check-typographie.py)")
    return droites


def controler(fichier):
    chemin = pathlib.Path(fichier)
    texte = chemin.read_text(encoding="utf-8")
    lignes = texte.split("\n")
    marque = sans_code(lignes)
    anomalies = []

    blocs = controler_fermetures(fichier, lignes, anomalies)
    tableaux = controler_tableaux(fichier, marque, anomalies)
    liste_titres = controler_hierarchie(fichier, marque, anomalies)
    controler_sections(fichier, liste_titres, anomalies)
    controler_ancres(fichier, texte, liste_titres, anomalies)
    droites = controler_texte(fichier, marque, anomalies)

    plus_longue = max(len(l) for l in lignes)
    print(f"{fichier} : {len(liste_titres)} titres, {tableaux} tableaux, {blocs} blocs de code, "
          f"{plus_longue} caracteres sur la plus longue ligne, {len(lignes)} lignes, "
          f"{droites} apostrophe(s) droite(s) restante(s)")
    return anomalies


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    anomalies = []
    for fichier in argv[1:]:
        anomalies += controler(fichier)
    if anomalies:
        print("\n--- ANOMALIES D'EXPORT PDF ---")
        for anomalie in anomalies:
            print("ECHEC", anomalie)
        return 1
    print("\nRESULTAT : supports prets pour l'export PDF")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
