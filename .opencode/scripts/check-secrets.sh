#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# check-secrets.sh : controle pre-commit, aucune credential externe dans le diff
#
# Usage :
#   .opencode/scripts/check-secrets.sh                # scan du diff indexe (git diff --cached)
#   .opencode/scripts/check-secrets.sh <fichier>...   # scan de fichiers ou repertoires precis
#
# Codes de sortie :
#   0 = aucune fuite detectee
#   1 = fuite detectee (commit bloque)
#   2 = usage invalide
#
# Perimetre : les credentials externes uniquement (tokens d'acces, mots de passe,
# cles privees, certificats, secrets de connexion, identifiants). Le contenu du
# cours, les segments et adresses de laboratoire, les ports de demonstration,
# les journaux simules du laboratoire et les noms d'outils ne sont PAS
# restreints : les signaler serait un faux positif permanent.
# ---------------------------------------------------------------------------
set -uo pipefail

# Motifs de haute confiance : format de credential exploitable
HIGH='ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|ghu_[A-Za-z0-9]{20,}|ghs_[A-Za-z0-9]{20,}|ghr_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|ya29\.[A-Za-z0-9_-]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}'

# Motifs de faible confiance : mots a verifier manuellement.
# `pwd` n'est retenu qu'assorti d'un signe egal ou deux-points : c'est ainsi
# qu'un mot de passe apparait (`password=...`, `pwd: ...`). Isole, le mot
# `pwd` est la commande shell qui affiche le dossier courant, presente dans
# toute documentation technique, et la faire signaler serait sans raison.
LOW='(password|passwd|pwd\s*[=:]|secret|token|api[_-]?key|apikey|authorization|bearer|credential)'

# Formes autorisees : valeurs de remplacement documentees.
# `<CLE_PUBLIE_SRV>` et `<A_COMPLETER>` rejoignent les formes deja tolerees :
# le cours de forensique fait manipuler des cles et des mots de passe, et
# chaque exemple doit rester un gabarit.
ALLOW='<[^>]*>|\{env:[A-Za-z_]+\}|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?|%[A-Za-z_]+%|xxxxx|XXXXX|CHANGEME|changeme|placeholder|PLACEHOLDER|REDACTED|redacted|\.\.\.|\*\*\*|votre_|VOTRE_|mon_token|exemple|EXAMPLE|a_completer|A_COMPLETER|\bTOKEN\b|\bPASSWORD\b|\bSECRET\b|\bAPI_KEY\b|\bSNMP_COMMUNITY\b'

scan() {
    # $1 = libelle, $2 = contenu
    local label="$1" content="$2" hits_high hits_low

    # Passe haute confiance : motifs de credential trop specifiques pour un faux positif
    hits_high=$(printf '%s\n' "$content" | grep -En "$HIGH" || true)

    hits_low=$(printf '%s\n' "$content" \
        | grep -E "$ALLOW" -v \
        | grep -Ein "$LOW" || true)

    if [ -n "$hits_high" ]; then
        printf 'FUTE DETECTEE (%s) : credential externe en clair\n%s\n\n' "$label" "$hits_high"
        RC=1
    fi
    if [ -n "$hits_low" ]; then
        printf 'A VERIFIER (%s) : mot sensible present, confirmer que la valeur est un exemple\n%s\n\n' "$label" "$hits_low"
    fi
}

RC=0

if [ "$#" -eq 0 ]; then
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        printf 'check-secrets: hors depot git et aucun fichier fourni\n' >&2
        exit 2
    fi
    if git diff --cached --quiet; then
        printf 'check-secrets: rien en zone index, aucun secret detecte\n'
        exit 0
    fi
    CONTENT=$(git diff --cached -U0 --no-color | grep -E '^\+' | grep -vE '^\+\+\+')
    scan "diff indexe" "$CONTENT"
else
    for target in "$@"; do
        if [ -d "$target" ]; then
            while IFS= read -r file; do
                scan "$file" "$(grep -n '' "$file" || true)"
            done < <(grep -rIl '' "$target" --exclude-dir=.git --exclude-dir=node_modules 2>/dev/null)
        elif [ -f "$target" ]; then
            scan "$target" "$(grep -n '' "$target" || true)"
        else
            printf 'check-secrets: fichier introuvable %s\n' "$target" >&2
            RC=2
        fi
    done
fi

if [ "$RC" -eq 0 ]; then
    printf 'check-secrets: aucune credential externe detectee\n'
fi

exit "$RC"