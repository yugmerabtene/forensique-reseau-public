#!/usr/bin/env python3
"""Détection de corruption de texte dans les supports de cours.

Recherche les artefacts typiques d'une génération automatique :
caractères étrangers, mots dépourvus d'accent, mots collés, mots diploués,
mélange de scripts, anglicismes et termes proscrits.

Ce contrôle ne se substitue pas à la relecture humaine : c'est un garde-fou.

Le contenu des blocs de code est exclu de l'analyse du français : une commande
contient des mots anglais par nature, et une apostrophe droite y est une
instruction pour le shell, pas une faute typographique.

Usage : python3 .opencode/scripts/check-texte.py jour-1.md jour-2.md jour-3.md
Code retour : 0 conforme, 1 artefact détecté, 2 usage invalide.
"""

import re
import sys

# Fragments anglais ou étrangers qui n'ont pas leur place dans un support
# français. Les noms d'outils, les protocoles et les abréviations sont exclus :
# ils sont légitimes et le cours les emploie.
_TERMES = [
    # Protocoles, formats et abréviations du domaine
    "PCAP", "PCAPNG", "BPF", "EVE", "IDS", "IPS", "SIEM", "DDoS", "RTT", "SNR",
    "TLS", "SSL", "ICMP", "TCP", "UDP", "HTTP", "HTTPS", "DNS", "SIP", "SLA",
    "QoS", "RTP", "ToS", "VoIP", "ACK", "DSCP", "MIB", "SNMP", "VLAN", "DHCP",
    "DMZ", "LAN", "WAN", "NAT", "FTP", "SFTP", "SMTP", "NTP", "LLDP", "MTU",
    "ARP", "MAC", "CIDR", "JSON", "YARA", "SYN", "RST", "FIN", "PSH", "URG",
    "IPv4", "IPv6", "HTTP", "RFC", "PCRE", "GRE", "VPN", "SSH", "RCE", "CVE",
    "C2", "APT", "PII", "RGPD", "CNIL", "NIS2",
    # Noms propres d'outils et de fichiers du laboratoire
    "tcpdump", "tshark", "wireshark", "nmap", "iperf3", "suricata", "zeek",
    "rsyslog", "splunk", "jq", "pcap", "mdev",
    # Mots anglais qui apparaissent dans les sorties d'outils citées
    "filtered", "denied", "timeout", "localhost", "uptime", "conn-refused",
    "policy", "reason", "Permission", "ip", "ss", "INPUT", "FORWARD", "OUTPUT",
    "PREROUTING", "POSTROUTING",
]
EXCLUS = re.compile(
    "|".join([
        r"`[^`]*`",                                    # code en ligne
        r"\b\d{1,3}(?:\.\d{1,3}){3}\b",                 # adresses IP
        r"\|",                                          # séparateurs de tableaux
        r"\b(?:" + "|".join(re.escape(t) for t in _TERMES) + r")\b",
        r"\blab\b",                                     # « lab » : acceptable
    ]),
    re.IGNORECASE,
)

INTERDITS = [
    (r"\b(plays|makes|gives|shows|needs|wants|looks|finds|founders|chosen)\b",
     "verbe anglais"),
    (r"\b(people|stuff|setup|dashboard|listing|check|demonstrations|exercises"
     r"|curiosity|retained|debate)\b", "anglicisme de confort"),
    (r"\b(metodo|metodo|método|senha|usuario|contrasenya|password|falha"
     r"|usuário|senhor)\b", "mot espagnol ou portugais"),
    (r"\b(log|logs)\b", "anglicisme de confort : log"),
    (r"\b(output|input)\b", "anglicisme de confort : output ou input"),
    (r"\b(the|and|with|from|this|that)\b", "mot anglais frequent"),
    (r"\b(must|should|shall|will|can|may|would)\b", "modal anglais"),
    ("[぀-ヿ一-鿿가-힯Ѐ-ӿ؀-ۿ]", "caractere etranger"),
    ("[\U0001F300-\U0001FAFF☀-➿️]", "emoji ou symbole"),
    (r"\bSéquence\b|\bséquence\b|\bsequences?\b", "terme proscrit : sequence"),
    (r"\bTP\b|\bTPs\b|\btravaux pratiques\b", "terme proscrit : TP"),
    (r"\bTODO\b|\bFIXME\b|\bXXX\b|\bLorem ipsum\b", "marqueur de brouillon"),
    (r"\bpreuve digitale\b", "terminologie : preuve numérique"),
    (r"\bforensique reseau\b", "orthographe : forensique réseau"),
    (r"\b\ttabulation\b", "tabulation"),
    (r"\.\.\.\s*$", "trois points en fin de ligne"),
]

# Mots sans accent : forme non accentuée d'un mot courant du support.
SANS_ACCENT = {
    "interpretation": "interprétation",
    "probleme": "problème",
    "general": "général",
    "systeme": "système",
    "methode": "méthode",
    "resultat": "résultat",
    "resultats": "résultats",
    "reference": "référence",
    "securite": "sécurité",
    "reseau": "réseau",
    "reseaux": "réseaux",
    "donnees": "données",
    "equipe": "équipe",
    "equipee": "équipée",
    "etape": "étape",
    "etapes": "étapes",
    "modele": "modèle",
    "critere": "critère",
    "criteres": "critères",
    "prealable": "préalable",
    "verifier": "vérifier",
    "controle": "contrôle",
    "role": "rôle",
    "periode": "période",
    "duree": "durée",
    "mesuree": "mesurée",
    "capturee": "capturée",
    "frequence": "fréquence",
    "debit": "débit",
    "enquete": "enquête",
    "enqueteur": "enquêteur",
    "periode": "période",
    "interet": "intérêt",
    "integrite": "intégrité",
    "confidentialite": "confidentialité",
    "disponibilite": "disponibilité",
    "tracabilite": "traçabilité",
}

# Mots collés : un mot collé à un mot suivant sans espace ni trait d'union.
COLLES = r"\b([a-zà-ÿ]{2,})([A-ZÀ-Þ][a-zà-ÿ]{1,})\b"

# Mots diploués : la même syllabe répétée par mégarde.
DIPLOME = r"\b([a-zà-ÿ]{3,})\1\b"

# Mots légitimes qui ressemblent à des erreurs.
AUTORISES = {
    a.lower() for a in {
        "chercher", "cherches", "cherchons", "appellees", "appelee", "appelées",
        "donnees", "donnee", "annnee", "annee", "annees", "hall", "elle",
        "elles", "pelle", "belle", "somme", "sonne", "tonne",
        "etre", "meme", "peme", "cote", "cotee", "coté", "cotes", "note",
        "notes", "notre", "votre", "notee", "tete", "tetee", "etes",
        "entete", "enchainee", "chaines", "chaine", "chainer",
        # CamelCase legitimes : sigles et noms d'outils a majuscule initiale
        "ipRoute", "ipAddr", "ipRouteShow", "ipNeigh", "macAddress",
        "tcpFlags", "ipv4", "ipv6",
    }
}

# Mots composés sans trait d'union, fréquents dans les textes générés.
COMPOSES = [
    "configurationissue", "rapportd", "règlesde", "étapesdu", "résultatattendu",
    "commandescomplètes", "sécuritéreseau", "réseauaudité", "forensiquereseau",
    "horodatagecaptures", "chainedelaconservation",
]


def analyser(chemin):
    with open(chemin, encoding="utf-8") as f:
        lignes = f.read().split("\n")
    anomalies = []
    dans_bloc = False
    for numero, ligne in enumerate(lignes, 1):
        if ligne.strip().startswith("```"):
            # Un bloc de code contient des commandes et des sorties d'outils :
            # tabulations et espaces en fin de ligne seulement, pas d'analyse
            # de francais. Le contenu du bloc est egalement ecarte, sans quoi
            # les operateurs de langages (`and`, `or`, `not`) et les en-tetes
            # JSON de Suricata seraient pris pour des mots anglais.
            if "\t" in ligne:
                anomalies.append(f"ligne {numero} : tabulation dans un bloc de code")
            if ligne.rstrip() != ligne and ligne.strip():
                anomalies.append(f"ligne {numero} : espace en fin de ligne")
            dans_bloc = not dans_bloc
            continue
        if dans_bloc:
            if "\t" in ligne:
                anomalies.append(f"ligne {numero} : tabulation dans un bloc de code")
            if ligne.rstrip() != ligne and ligne.strip():
                anomalies.append(f"ligne {numero} : espace en fin de ligne")
            continue
        # Le code en ligne et les termes techniques legitimés sont neutralises.
        # L'identite d'un compte d'acces au laboratoire precede une adresse : elle est
        # volontairement sans accent (enqueteur@10.10.0.10). Le couple est donc
        # neutralise avant l'analyse du francais. Le retrait a lieu sur la ligne
        # brute, car le motif des adresses a deja ete remplace plus haut.
        sans_identite = re.sub(r"[\w-]+@(?:\d{1,3}\.){3}\d{1,3}", " ", ligne)
        texte = EXCLUS.sub(" ", sans_identite)
        # Les adresses, les chemins et les noms de fichier sont eux aussi
        # neutralises : le dossier ~/enquete/ et le fichier inventaire-hotes.txt
        # ne sont pas des fautes, ce sont des noms d'objets. Un mot colle a l'un
        # d'eux par un tiret bas cesse en revanche d'etre un mot du texte
        # courant, et reste signale.
        prose = re.sub(r"https?://\S+", " ", texte)
        prose = re.sub(r"[~\w.-]*(?:/[\w./~%-]*)+", " ", prose)
        prose = re.sub(r"[\w-]+\.(?:txt|md|pcap|sh|py|log|json|csv|yaml|yml|conf|sha256)\b",
                       " ", prose)
        for motif, libelle in INTERDITS:
            for m in re.finditer(motif, texte, re.IGNORECASE):
                extrait = texte.strip()[max(0, m.start() - 30):m.end() + 30]
                anomalies.append(f"ligne {numero} : {libelle} : ...{extrait}...")
        # Un tiret bas entre deux lettres est un artefact dans le texte courant.
        # Il reste legitime dans une URL, un chemin ou un nom de fichier : ces
        # trois formes sont neutralisees dans `prose` avant le controle. Un mot
        # colle comme « audit_restreint » ne correspond a aucune d'elles et reste
        # signale.
        for m in re.finditer(r"[a-zà-ÿ]_[a-zà-ÿ]", prose):
            extrait = prose[max(0, m.start() - 30):m.end() + 30]
            anomalies.append(f"ligne {numero} : mot colle par un tiret bas : "
                             f"...{extrait.strip()}...")
        for m in re.finditer(COLLES, prose):
            if m.group(0).lower() not in AUTORISES:
                anomalies.append(f"ligne {numero} : mots collés : {m.group(0)!r}")
        for m in re.finditer(DIPLOME, texte):
            if m.group(0).lower() not in AUTORISES:
                anomalies.append(f"ligne {numero} : mot diploué : {m.group(0)!r}")
        for mot in COMPOSES:
            if mot in texte.lower():
                anomalies.append(f"ligne {numero} : composé sans trait d'union : {mot!r}")
        for sans, avec in SANS_ACCENT.items():
            motif = rf"(?<![\wÀ-ÿ-]){re.escape(sans)}(?![\wÀ-ÿ-])"
            if re.search(motif, prose, re.IGNORECASE):
                anomalies.append(f"ligne {numero} : accent manquant : "
                                 f"{sans!r} -> {avec!r}")
        if ligne.rstrip() != ligne and ligne.strip():
            anomalies.append(f"ligne {numero} : espace en fin de ligne")
    return anomalies


def main(argv):
    if len(argv) < 2:
        print("usage : check-texte.py fichier.md [fichier.md ...]")
        return 2
    total = 0
    for chemin in argv[1:]:
        try:
            anomalies = analyser(chemin)
        except FileNotFoundError:
            print(f"ECHEC {chemin} : fichier absent")
            return 2
        total += len(anomalies)
        print(f"{chemin} : {len(anomalies)} anomalie(s)")
        for a in anomalies:
            print("  ANOMALIE", a)
    if total:
        print(f"\nRESULTAT : {total} anomalie(s) de texte")
        return 1
    print("\nRESULTAT : texte conforme")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))