#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# export-pdf.sh : construit les PDF du cours a partir des supports Markdown.
#
# Usage :
#   bash .opencode/scripts/export-pdf.sh            # les trois jours
#   bash .opencode/scripts/export-pdf.sh jour-2.md   # un seul support
#
# Les PDF sont des artefacts de construction : ils sont ecrits dans export/ et
# ne sont pas versionnes. Seuls le script et le fragment de mise en page le
# sont, pour que le rendu soit reproductible d'une machine a l'autre.
# ---------------------------------------------------------------------------
set -euo pipefail

RACINE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SORTIE="$RACINE/export"
FRAGMENT="$RACINE/.opencode/export/mise-en-page.tex"
LOGO="$RACINE/.opencode/export/logo-ascent.png"

# --- outillage ---------------------------------------------------------------
# pandoc et XeLaTeX sont installes en espace utilisateur, sans privileges
# administrateur : le binaire de pandoc dans ~/.local, TinyTeX dans ~/.TinyTeX.
ajouter_au_chemin() {
    case ":$PATH:" in
        *":$1:"*) ;;
        *) PATH="$1:$PATH" ;;
    esac
}
ajouter_au_chemin "$HOME/.local/bin"
ajouter_au_chemin "$HOME/.TinyTeX/bin/x86_64-linux"
ajouter_au_chemin "$HOME/.TinyTeX/bin/$(uname -m)-linux"
export PATH

erreur() { printf 'export-pdf : %s\n' "$1" >&2; exit 1; }
info()   { printf '  %s\n' "$1"; }

# Compter les pages d'un PDF sans outil externe. La commande pdfinfo n'est pas
# presente, et le nombre de pages ne se lit pas dans le texte brut : il est
# cache dans des flux compresses. On les decompresse donc tous, puis on lit
# l'arbre des pages. Deux methodes doivent s'accorder, sinon le fichier est
# juge suspect plutot que presente comme valide.
compter_pages() {
    python3 - "$1" <<'PY'
import re, sys, zlib

donnees = open(sys.argv[1], "rb").read()
if not donnees.startswith(b"%PDF-"):
    sys.exit(1)

morceaux = []
for motif in re.finditer(rb"stream\r?\n(.*?)endstream", donnees, re.S):
    try:
        morceaux.append(zlib.decompress(motif.group(1)))
    except zlib.error:
        morceaux.append(motif.group(1))
tout = b"\n".join(morceaux)

feuilles = len(re.findall(rb"/Type\s*/Page(?![s])", tout))
comptes = [int(n) for n in
           re.findall(rb"/Type\s*/Pages\b[^>]{0,300}?/Count\s+(\d+)", tout, re.S)]
if not comptes:
    print(feuilles or 0)
elif feuilles and feuilles != max(comptes):
    # Les deux lectures divergent : on signale, on ne devine pas.
    print(0)
else:
    print(max(comptes) or feuilles)
PY
}

command -v pandoc  >/dev/null 2>&1 || erreur "pandoc est absent. Voir .opencode/export/LISEZ-MOI.md pour l'installation en espace utilisateur."
command -v xelatex >/dev/null 2>&1 || erreur "XeLaTeX est absent. Voir .opencode/export/LISEZ-MOI.md pour l'installation en espace utilisateur."
# pdftotext (poppler-utils) sert au controle de completude : sans lui, on ne
# peut pas prouver que le PDF contient bien tous les titres du support.
command -v pdftotext >/dev/null 2>&1 || erreur "pdftotext est absent. Installer poppler-utils : sudo apt install poppler-utils"
[ -f "$FRAGMENT" ] || erreur "fragment de mise en page absent : $FRAGMENT"
# Le logo figure sur la couverture et dans l'en-tete de chaque page. Son
# absence ne doit pas passer inapercue : un support livre sans l'identite du
# prestataire n'est pas diffusable.
[ -f "$LOGO" ] || erreur "logo du prestataire absent : $LOGO. Voir .opencode/export/LISEZ-MOI.md."

mkdir -p "$SORTIE"

# --- supports a convertir ----------------------------------------------------
if [ "$#" -gt 0 ]; then
    SUPPORTS=("$@")
else
    SUPPORTS=(jour-1.md jour-2.md jour-3.md)
fi

# Resoudre le chemin d'un support. L'argument est accepte tel quel, ou relatif
# a la racine du depot : la premiere forme permet de convertir un support de
# travail place ailleurs. Cette fonction est appelee par les deux boucles
# suivantes, chacune devant redeployer son propre chemin : une variable
# reutilisee d'une boucle a l'autre conservait le dernier support examine, et
# pandoc convertissait alors le jour 2 dans le fichier du jour 1. Le controle
# de completude l'a detecte, mais mieux vaut ne pas dependre de lui.
resoudre_support() {
    if [ -f "$1" ]; then
        printf '%s' "$1"
    elif [ -f "$RACINE/$1" ]; then
        printf '%s' "$RACINE/$1"
    else
        erreur "support introuvable : $1"
    fi
}

# --- verification prealable des supports -------------------------------------
# On ne lance pas une conversion sur un support qui ne respecte pas les regles
# du cours : le PDF reproduirait fidelement une faute de structure.
for support in "${SUPPORTS[@]}"; do
    CHEMIN="$(resoudre_support "$support")"
    python3 "$RACINE/.opencode/scripts/check-pdf.py" "$CHEMIN" >/dev/null \
        || erreur "$support ne passe pas le controle de preparation au PDF. Le lancer d'abord."
done

# Écrire les paramètres propres à un support : la journée, sa date et son thème.
# Ces trois valeurs n'existent que dans le support lui-même, au sein du titre
# du jour et du titre de la journée. Les extraire ici évite de les recopier dans
# le script, où elles se désynchroniseraient à la première modification d'un
# support.
#
# Les caractères réservés de LaTeX sont échappés : un thème contenant une
# esperluette ou un souligné interromprait sinon la compilation, et le défaut
# apparaîtrait bien plus tard, sur un support sans rapport.
ecrire_parametres() {
    python3 - "$1" "$2" "$LOGO" <<'PY'
import pathlib, re, sys

support, destination, logo = sys.argv[1], sys.argv[2], sys.argv[3]
lignes = pathlib.Path(support).read_text(encoding="utf-8").splitlines()


def premier(motif):
    for ligne in lignes:
        m = re.match(motif, ligne)
        if m:
            return m.group(1).strip()
    return ""


def echapper(texte):
    return re.sub(r"([\\&%$#_{}~^])", r"\\\1", texte)


jour = premier(r"^#\s+.*?[—–-]\s*(JOUR\s+\d+)")
# Le titre du support porte l'intitule et la journee dans la meme ligne, par
# exemple « Audit et Analyse des Réseaux — JOUR 1 ». La couverture les presente
# sur deux lignes distinctes, l'intitule en grand et la journee en rouge : on
# ne garde donc ici que ce qui precede la journee.
intitule = premier(r"^#\s+(.+?)\s*$")
intitule = re.sub(r"\s*[—–-]\s*JOUR\s+\d+\s*$", "", intitule)
theme_complet = premier(r"^##\s+(.+)$")
date = ""
m = re.search(r"\(([^()]*/\d{4})\)", theme_complet)
if m:
    date = m.group(1)
theme = re.sub(r"\s*\([^()]*\)\s*$", "", theme_complet)

valeurs = (("ascentlogo", logo), ("ascentintitule", intitule),
           ("ascentjour", jour), ("ascentdate", date), ("ascenttheme", theme))
# \def, et non \providecommand : le fragment de mise en page definit deja ces
# commandes avec des valeurs de repli, et \providecommand ne remplace pas une
# definition existante. Les valeurs de repli resteraient donc utilisees, et le
# logo comme le theme de la journee resteraient vides.
corps = "\n".join(f"\\def\\{cle}{{{echapper(valeur)}}}"
                  for cle, valeur in valeurs)
pathlib.Path(destination).write_text(corps + "\n", encoding="utf-8")
PY
}

# Poser les repères de lecture dans le .tex produit par Pandoc, juste avant la
# compilation. Un chapitre ouvre une page, et la rubrique qui nomme le livrable
# d'un laboratoire porte une pastille verte.
#
# Le travail se fait ici, et non dans le fragment de mise en page, parce que le
# texte d'un titre n'est pas lisible depuis LaTeX sans casser le rendu : le
# fragment tente l'affaire, et ses commentaires expliquent pourquoi il renonce.
# Le script, lui, voit le .tex et sait exactement ou se trouve chaque titre.
#
# Les titres de laboratoire ne recoivent pas de pastille : ils commencent déjà
# par le mot « LAB », et une pastille « LAB » posée à côté d'un titre « LAB »
# se lirait comme une faute. Le trait rouge sous les titres de chapitre suffit
# à les distinguer.
post_traiter_tex() {
    python3 - "$1" <<'PY'
import pathlib, re, sys

chemin = pathlib.Path(sys.argv[1])
lignes = chemin.read_text(encoding="utf-8").splitlines(keepends=True)


def titre_simple(texte):
    """Un titre Pandoc, débarrassé de la mise en forme de la source."""
    return re.sub(r"\\([*_`]| emph | strong )", "", texte).strip()


sortie = []
for ligne in lignes:
    m = re.match(r"\\section\{([^}]*)\}", ligne)
    if m and titre_simple(m.group(1)).startswith("Chapitre"):
        sortie.append("\\clearpage\n")
    m = re.match(r"\\subsection\{([^}]*)\}", ligne)
    if m and titre_simple(m.group(1)).startswith("Ce que ce LAB produit"):
        ligne = ligne.replace(
            "\\subsection{",
            "\\subsection{\\ascentpastille{livrable}{LIVRABLE}\\hspace{0.45em}", 1)
    sortie.append(ligne)
chemin.write_text("".join(sortie), encoding="utf-8")
PY
}

# Verifier que rien ne s'est perdu a la conversion. On extrait le texte du PDF
# et on y cherche chaque titre du support. C'est le seul controle qui prouve que
# le rendu est complet : une page qui disparaitrait, un titre tronque ou un
# tableau coupe ne se verrait pas sur le nombre de pages.
#
# La comparaison ignore la casse, les accents, la ponctuation et les traits
# d'union de fin de ligne, que LaTeX insere pour couper un mot entre deux
# lignes. Sans cette normalisation, un titre correct serait declare absent.
verifier_contenu() {
    local support="$1" pdf="$2" rapport
    rapport="$(python3 - "$1" "$2" <<'PY'
import re, subprocess, sys, unicodedata

support, pdf = sys.argv[1], sys.argv[2]

def normaliser(texte):
    texte = unicodedata.normalize("NFKD", texte)
    texte = "".join(c for c in texte if not unicodedata.combining(c))
    return "".join(c.lower() for c in texte if c.isalnum())

markdown = open(support, encoding="utf-8").read()
extrait = subprocess.run(["pdftotext", "-q", pdf, "-"],
                         capture_output=True, text=True).stdout
rendu = normaliser(extrait)

titres = []
dans_code = False
for ligne in markdown.splitlines():
    if ligne.startswith("```"):
        dans_code = not dans_code
        continue
    if dans_code:
        continue
    m = re.match(r"^(#{1,6})\s+(.+?)\s*$", ligne)
    if m:
        titres.append(re.sub(r"[`*_]", "", m.group(2)))

absents = [t for t in titres if normaliser(t) and normaliser(t) not in rendu]
for t in absents:
    print("absent\t" + t)
print("total\t%d" % len(titres))
print("absents\t%d" % len(absents))
PY
)"

    local total absents
    total="$(printf '%s\n' "$rapport"   | awk -F'\t' '$1=="total"{print $2}')"
    absents="$(printf '%s\n' "$rapport" | awk -F'\t' '$1=="absents"{print $2}')"
    printf '%s\n' "$rapport" | awk -F'\t' '$1=="absent"{print "  titre absent du PDF : " $2}'

    [ "${absents:-1}" = "0" ] || erreur "$pdf : $absents titre(s) du support absents du rendu. Conversion incomplete."
    info "contenu  $total titres vérifiés, aucun absent"
}

# Verifier la mise en page elle-meme, et non seulement la presence du texte.
# Un document peut contenir tous ses titres et rester mal mis en page : c'est
# exactement ce qui est arrive tant que le saut de page des chapitres et les
# pastilles de livrable n'etaient pas poses. Ce controle examine donc le rendu,
# page par page, et verifie trois choses :
#   - chaque chapitre commence une page ;
#   - chaque livrable porte sa pastille ;
#   - le logo est present sur toutes les pages.
#
# Un chapitre est recherche page par page, en ignorant la table des matieres
# (deux pages) et la couverture. Le titre est recherche au debut d'une page, et
# non dans son texte entier : c'est la position qui distingue un titre de corps
# d'une simple mention.
verifier_rendu() {
    local support="$1" pdf="$2" rapport
    rapport="$(python3 - "$1" "$2" <<'PY'
import pathlib, re, subprocess, sys, unicodedata

support, pdf = sys.argv[1], sys.argv[2]


def normaliser(texte):
    texte = unicodedata.normalize("NFKD", texte)
    texte = "".join(c for c in texte if not unicodedata.combining(c))
    return "".join(c.lower() for c in texte if c.isalnum())


def nombre_pages(chemin):
    sortie = subprocess.run(["pdfinfo", chemin], capture_output=True, text=True)
    m = re.search(r"Pages:\s*(\d+)", sortie.stdout)
    return int(m.group(1)) if m else 0


def texte_page(chemin, page):
    return subprocess.run(
        ["pdftotext", "-f", str(page), "-l", str(page), chemin, "-"],
        capture_output=True, text=True).stdout


pages = [texte_page(pdf, p) for p in range(1, nombre_pages(pdf) + 1)]

# Les titres attendus, lus dans la source. Seuls les niveaux deux et trois
# interessent la mise en page : ce sont eux qui deviennent sections et
# rubriques.
titres = []
dans_code = False
for ligne in pathlib.Path(support).read_text(encoding="utf-8").splitlines():
    if ligne.startswith("```"):
        dans_code = not dans_code
        continue
    if dans_code:
        continue
    m = re.match(r"^(#{2,3})\s+(.+?)\s*$", ligne)
    if m:
        titres.append((len(m.group(1)), re.sub(r"[`*_]", "", m.group(2))))

# La table des matieres recopie les titres, et la couverture porte le theme :
# ni l'une ni l'autre ne prouve une mise en page. On ne les considere donc pas.
corps = pages[2:]

definitions = []
for numero, page in enumerate(corps, 3):
    lignes = [l.strip() for l in page.splitlines() if l.strip()]
    # La premiere ligne utile est l'en-tete, qui rappelle la section precedente.
    # Le titre d'un chapitre occupe l'une des lignes suivantes : la fenetre va
    # jusqu'a la sixieme, ce qui laisse le titre, son trait rouge et les deux
    # premieres lignes du preambule. Un titre retrouve dans cette fenetre est
    # donc en tete de page ; retrouve plus bas, il serait au milieu d'un
    # chapitre, et la mise en page serait fausse.
    definitions.append((numero, normaliser(" ".join(lignes[1:7]))))

problemes = []

for niveau, titre in titres:
    attendu = normaliser(titre)
    if niveau != 2 or not attendu.startswith("chapitre"):
        continue
    if not any(attendu in fenetre for _, fenetre in definitions):
        problemes.append("chapitre absent du haut d'une page : " + titre)

# Une pastille de livrable par rubrique « Ce que ce LAB produit ». On les compte
# dans le texte extrait : chaque pastille produit le mot une fois dans le corps
# et une fois dans la table des matieres.
rendu = " ".join(pages)
attendus = sum(1 for n, t in titres
               if normaliser(t).startswith("cequecelabproduit"))
trouves = rendu.count("LIVRABLE")
if trouves < attendus:
    problemes.append("pastilles de livrable absentes : %d attendues, %d trouvées"
                     % (attendus, trouves))

# Le logo : une image par page, celle de l'en-tete. La couverture porte aussi
# le logo, dans son bandeau, elle compte donc comme les autres pages.
# pdfimages liste page par page : un logo pose deux fois sur la meme page
# compterait double dans un comptage global, on verifie donc chaque page.
for numero in range(1, len(pages) + 1):
    n = subprocess.run(["pdfimages", "-list", "-f", str(numero), "-l", str(numero),
                        pdf], capture_output=True, text=True).stdout
    if not [l for l in n.splitlines()[2:] if l.strip()]:
        problemes.append("aucune image, donc aucun logo, page %d" % numero)

for p in problemes:
    print("defaut\t" + p)
print("chapitres\t%d" % sum(1 for n, t in titres
                             if n == 2 and normaliser(t).startswith("chapitre")))
print("livrables\t%d" % attendus)
print("pages\t%d" % len(pages))
print("problemes\t%d" % len(problemes))
PY
)"

    local problemes chapitres livrables pages
    problemes="$(printf '%s\n' "$rapport" | awk -F'\t' '$1=="problemes"{print $2}')"
    chapitres="$(printf '%s\n' "$rapport" | awk -F'\t' '$1=="chapitres"{print $2}')"
    livrables="$(printf '%s\n' "$rapport" | awk -F'\t' '$1=="livrables"{print $2}')"
    pages="$(printf '%s\n' "$rapport" | awk -F'\t' '$1=="pages"{print $2}')"

    printf '%s\n' "$rapport" | awk -F'\t' '$1=="defaut"{print "  mise en page : " $2}'
    [ "${problemes:-1}" = "0" ] \
        || erreur "$pdf : $problemes défaut(s) de mise en page. Rendu incomplet."
    info "mise en page  $chapitres chapitres en tête de page, $livrables livrables pastillés, logo sur $pages pages"
}

# --- conversion --------------------------------------------------------------

# La conversion se fait en deux temps, et non par la commande directe de pandoc
# vers le PDF. Cette commande avale le journal LaTeX : on ne verrait alors ni les
# debordements de tableau, ni les avertissements de police. En gardant le .tex
# et le .log, on sait ce qui deborde et ou, ce qui est la seule information utile
# pour juger un premier rendu.
for support in "${SUPPORTS[@]}"; do
    CHEMIN="$(resoudre_support "$support")"
    # Le nom de sortie ne garde que le nom du fichier. Sans cela, un support
    # donne par son chemin complet ecirait ses artefacts dans export//tmp/...,
    # un chemin qui n'existe pas.
    nom="$(basename "${support%.md}")"
    tex="$SORTIE/$nom.tex"
    pdf="$SORTIE/$nom.pdf"
    log="$SORTIE/$nom.log"

    # Le journal est tronque a chaque conversion : deux lancements successifs
    # n'ont pas a melanger leurs avertissements, sinon on ne sait plus si un
    # débordement vient du rendu d'aujourd'hui ou de celui de la semaine derniere.
    : >"$log"

    # Les fichiers auxiliaires d'une conversion anterieure sont supprimes. La
    # table des matieres, les renvois et les signets sont relus depuis ces
    # fichiers : un .aux laisse par un lancement interrompu, ou ecrit sous un
    # autre nom de support, peut alors decrire un document qui n'existe plus.
    # Chaque conversion part d'un etat vierge, donc d'un rendu reproductible.
    rm -f "$SORTIE/$nom.aux" "$SORTIE/$nom.toc" "$SORTIE/$nom.out"

    # Les parametres propres au support alimentent la couverture : journee,
    # date et theme. Ils sont ecrits dans un fichier a part, injecte lui aussi
    # en en-tete, pour que le fragment de mise en page reste identique pour les
    # deux journees.
    parametres="$SORTIE/$nom-parametres.tex"
    ecrire_parametres "$CHEMIN" "$parametres"

    # Les schemas Mermaid sont rendus en PDF vectoriel avant la conversion.
    # Pandoc ne sait pas les interpreter : sans cette etape, il recopierait le
    # code source du schema dans le document, et LaTeX detruirait les fleches.
    info "schemas  $support"
    support_avec_schemas="$(python3 "$RACINE/.opencode/scripts/rendre-schema.py" \
        "$CHEMIN" "$SORTIE/schemas/$nom")" \
        || erreur "les schemas de $support n'ont pas pu etre rendus"

    info "pandoc  $support -> $nom.tex"
    pandoc "$support_avec_schemas" \
        --from=markdown+pipe_tables+implicit_figures+raw_html+autolink_bare_uris \
        --to=latex \
        --standalone \
        --toc \
        --number-sections=false \
        --shift-heading-level-by=-1 \
        --wrap=preserve \
        --resource-path="$RACINE" \
        -V documentclass=article \
        -V papersize=a4 \
        -V fontsize=10pt \
        -V geometry:margin=2cm \
        -V geometry:headheight=18pt \
        -V lang=fr \
        -V toc-title=Sommaire \
        -V linkcolor=blue \
        -V urlcolor=blue \
        -V colorlinks=true \
        -M pagetitle="Audit et analyse des réseaux — ${nom#jour-}" \
        --include-in-header="$FRAGMENT" \
        --include-in-header="$parametres" \
        -o "$tex" || erreur "pandoc n'a pas su convertir $support"

    # Les reperes de lecture sont poses sur le .tex, avant les deux passes de
    # XeLaTeX. Le faire apres la premiere passe donnerait deux rendus
    # differents pour un meme support, puisque la seconde recharge le .toc ecrit
    # par la premiere.
    post_traiter_tex "$tex"

    # Deux passes : la premiere ecrit la table des matieres, la seconde y inscrit
    # les numeros de page, qui ne sont connus qu'une fois la premiere terminee.
    for passe in 1 2; do
        xelatex -interaction=nonstopmode -halt-on-error \
            -output-directory="$SORTIE" "$tex" >>"$log" 2>&1 \
            || erreur "XeLaTeX a echoue sur $support, passe $passe. Journal : $log"
    done

    [ -s "$pdf" ] || erreur "$pdf est vide apres conversion"

    pages="$(compter_pages "$pdf")"
    [ "${pages:-0}" -gt 0 ] || erreur "$pdf ne déclare aucune page : le rendu a échoué."
    verifier_contenu "$support" "$pdf"
    verifier_rendu "$support" "$pdf"

    # Les debordements sont le vrai risque d'un support a tableaux larges. On
    # les compte et on indique le pire, pour savoir quoi regarder a l'ouverture.
    debordements="$(grep -c 'Overfull \\hbox' "$log" 2>/dev/null || true)"
    pire="$(grep -oE 'Overfull \\hbox \([0-9.]+pt' "$log" 2>/dev/null \
            | grep -oE '[0-9.]+' | sort -rn | head -1 || true)"
    taille="$(du -h "$pdf" | cut -f1)"

    info "résultat  $nom.pdf — $pages pages, $taille"
    if [ "${debordements:-0}" -gt 0 ]; then
        info "débordements  $debordements lignes trop longues, la plus forte de ${pire:-?} pt"
    else
        info "débordements  aucun"
    fi
done

printf '\n%s\n' "export-pdf : les PDF sont dans $SORTIE"
