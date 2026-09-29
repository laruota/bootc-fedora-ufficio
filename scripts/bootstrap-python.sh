#!/usr/bin/env bash
# Bootstrap Python tools/libraries on the target machine (first-run setup).
# Run as a normal user, never via sudo. Installs to ~/.local (user site-packages).
set -euo pipefail

if [ "$EUID" -eq 0 ]; then
    echo "Esegui questo script come utente normale, senza sudo." >&2
    exit 1
fi

# Librerie richieste dagli script Nautilus (vedi setup-alma10/71-nautilus-scripts.yml)
python3 -m pip install --user --break-system-packages --upgrade pdfplumber

# Tool CLI via pipx (mat2 per l'anonimizzazione metadati)
command -v pipx >/dev/null 2>&1 && pipx install mat2
