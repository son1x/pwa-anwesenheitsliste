#!/bin/bash
# rendern.sh - setzt Werte in eine Apache-Vorlage ein (@NAME@ -> Wert).
#   bash rendern.sh vorlage.conf.in NAME=wert ... > ziel.conf
# Bricht ab, wenn danach noch ein @PLATZHALTER@ übrig ist.
# Benutzt von deploy/vserver-setup.sh.
set -euo pipefail
vorlage="$1"; shift
inhalt="$(cat "$vorlage")"
for paar in "$@"; do
    name="${paar%%=*}"
    wert="${paar#*=}"
    inhalt="${inhalt//@${name}@/${wert}}"
done
if rest="$(grep -o '@[A-Z_]*@' <<<"$inhalt")"; then
    echo "rendern.sh: nicht ersetzt in $vorlage: $(sort -u <<<"$rest" | tr '\n' ' ')" >&2
    exit 1
fi
printf '%s\n' "$inhalt"