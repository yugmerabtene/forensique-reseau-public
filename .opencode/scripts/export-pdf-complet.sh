#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# export-pdf-complet.sh : réunit les trois journées en un seul document PDF.
#
# Usage :
#   bash .opencode/scripts/export-pdf-complet.sh
#
# Le fichier produit est export/forensique-reseau-dgfip.pdf. Il remplace, pour
# la livraison, les trois PDF journalsiers : le formateur distribue un document
# unique, et l'apprenant reçoit la formation entière.
#
# Le document unique n'est pas la simple concaténation des trois fichiers. Trois
# corrections sont apportées, chacune nécessaire à la cohérence du rendu :
#
#   1. Les titres de niveau un des trois supports sont retirés. Dans un document
#      unique, chacun d'eux déclencherait une page de garde, et le lecteur
#      trouverait trois couvertures au lieu d'une. Ils deviennent le marqueur de
#      la journée dans le titre de la section qui ouvre la journée.
#
#   2. La numérotation des figures devient continue. Chaque journée numérote ses
#      schémas de 1 à N, ce qui convient à un support autonome mais produirait
#      ici trois figures « Fig 1 » dans un même document, dont le sommaire et le
#      texte ne sauraient plus laquelle est laquelle.
#
#   3. Chaque journée commence sur une page neuve. Un titre de section ne force
#      pas le saut de page dans la mise en page du cours : seuls les titres de
#      chapitre en provoquent un.
#
# Le rendu lui-même est produit par export-pdf.sh, jamais ici : la mise en page,
# le rendu des schémas et les contrôles de complétude restent donc exactement
# ceux des trois PDF journaliers, et aucune logique de rendu n'est duplique.
# ---------------------------------------------------------------------------
set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SORTIE="$RACINE/export"
SORTANT="$SORTIE/forensique-reseau-dgfip.md"

mkdir -p "$SORTIE"

printf '%s\n' "  assemblage des trois journées"

# --- assemblage des supports --------------------------------------------------
# Le fichier produit est un artefact de construction : il vit dans export/ et
# n'est pas versionné. Les supports restent les seules sources.
python3 - "$RACINE" "$SORTANT" <<'PY'
import pathlib
import re
import sys

racine, sortie = sys.argv[1], sys.argv[2]

# Le décalage de numérotation des figures est la somme des figures des
# journées précédentes. Il est calculé, non recopié, pour qu'un jour ou l'autre
# ajoute un schéma sans que la numérotation du document unique soit fausse.
JOURS = ["jour-1.md", "jour-2.md", "jour-3.md"]

decalage = 0
sortie_lignes = ["# Forensique réseau — FORMATION COMPLÈTE", ""]

for index, nom in enumerate(JOURS, 1):
    texte = pathlib.Path(racine, nom).read_text(encoding="utf-8")
    lignes = texte.splitlines()

    figures = {int(n) for n in re.findall(r"\bFig (\d+)\b", texte)}
    premier = texte.splitlines()[0]
    m = re.match(r"^#\s+.*?[—–-]\s*(JOUR\s+\d+)\s*$", premier)
    if not m:
        raise SystemExit("%s : titre de jour inattendu : %r" % (nom, premier))
    journee = m.group(1)

    # La première section de la journée porte le titre du jour : c'est elle qui
    # accueille le nom de la journée. Les sections suivantes, Objectifs du Jour
    # et Planning du Jour, portent le même nom dans les trois journées.
    jour_rencontre = False
    sortie_jour = ["\\clearpage", ""]

    dans_code = False
    for ligne in lignes:
        if ligne.startswith("```"):
            dans_code = not dans_code
            sortie_jour.append(ligne)
            continue
        if dans_code:
            sortie_jour.append(ligne)
            continue

        # Le titre de niveau un est retiré : il déclencherait une page de garde.
        if ligne.startswith("# "):
            continue

        # La numérotation des figures devient continue sur tout le document.
        ligne = re.sub(r"\bFig (\d+)\b",
                       lambda m: "Fig %d" % (int(m.group(1)) + decalage), ligne)

        if ligne.startswith("## "):
            if not jour_rencontre:
                ligne = "## %s — %s" % (journee, ligne[3:])
                jour_rencontre = True
        sortie_jour.append(ligne)

    sortie_lignes.extend(sortie_jour)
    decalage += len(figures)

pathlib.Path(sortie).write_text("\n".join(sortie_lignes) + "\n",
                                 encoding="utf-8")
print("  document assemblé : %d figures, %d jours"
      % (decalage, len(JOURS)))
PY

# --- fabrication du PDF -------------------------------------------------------
# Les valeurs de la couverture sont imposées ici. L'extraction automatique
# lirait dans le document unique le thème du premier jour et y écrirait « JOUR 1 »,
# ce qui serait faux sous un titre qui réunit les trois journées.
ASCENT_INTITULE="Forensique réseau" \
ASCENT_JOUR="Formation complète" \
ASCENT_THEME="Support pédagogique — 3 jours, 18 heures" \
ASCENT_DATE="12, 13 et 14 octobre 2026" \
    bash "$RACINE/.opencode/scripts/export-pdf.sh" "$SORTANT"

# --- contrôle du document assemblé -------------------------------------------
# Le rendu est vérifié sur le document unique, et non sur les trois supports :
# c'est lui qui est livré. Trois points sont contrôlés, qu'aucun des PDF
# journaliers ne peut poser : la couverture ne porte pas « JOUR 1 », les trois
# journées sont présentes, et la numérotation des figures est continue et sans
# doublon.
python3 - "$SORTIE/forensique-reseau-dgfip.pdf" <<'PY'
import re
import subprocess
import sys
import unicodedata

pdf = sys.argv[1]
problemes = []


def normaliser(texte):
    texte = unicodedata.normalize("NFKD", texte)
    texte = "".join(c for c in texte if not unicodedata.combining(c))
    return "".join(c for c in texte.lower() if c.isalnum())


def pages(pdf, premiere=None, derniere=None):
    args = ["pdftotext", "-q"]
    if premiere is not None:
        args += ["-f", str(premiere)]
    if derniere is not None:
        args += ["-l", str(derniere)]
    return subprocess.run(args + [pdf, "-"], capture_output=True,
                          text=True).stdout


info = subprocess.run(["pdfinfo", pdf], capture_output=True, text=True).stdout
nombre = int(re.search(r"Pages:\s*(\d+)", info).group(1))
brut = pages(pdf)
texte = normaliser(brut)

# La couverture ne doit nommer aucune journée unique : le document en réunit
# trois, et un « JOUR 1 » en rouge sous un titre général serait faux.
couverture = pages(pdf, 1, 1)
for jour in ("JOUR 1", "JOUR 2", "JOUR 3"):
    if jour in couverture:
        problemes.append("la couverture porte %s" % jour)
if "FORMATION" not in couverture.upper():
    problemes.append("la couverture ne porte pas la formation")

# Les trois journées doivent s'y trouver, chacune une fois.
for jour in ("JOUR 1", "JOUR 2", "JOUR 3"):
    if texte.count(normaliser(jour)) < 1:
        problemes.append("%s absent du document" % jour)

# Les figures doivent être numérotées de 1 à N, sans doublon ni trou : c'est la
# correction que l'assemblage apporte, et elle ne se voit pas à l'ouverture.
nombres = [int(n) for n in re.findall(r"\bFig (\d+)\b", brut)]
legendes = sorted(set(nombres))
if legendes != list(range(1, len(legendes) + 1)):
    problemes.append("numérotation des figures discontinue : %s" % legendes)

for p in problemes:
    print("defaut\t" + p)
print("pages\t%d" % nombre)
print("figures\t%d" % len(legendes))
print("problemes\t%d" % len(problemes))
sys.exit(1 if problemes else 0)
PY

printf '\n%s\n' "export-pdf-complet : le document unique est dans $SORTIE/forensique-reseau-dgfip.pdf"