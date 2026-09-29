#!/usr/bin/env bash
# Bootstrap flatpaks system-wide on the target machine (first-run setup).
# Run as a normal user (sudo is used internally). Flatpaks land in
# /var/lib/flatpak (machine state) and update independently of the OS.
# Edit the FLATPAKS / CUSTOM_FLATPAKS lists to match the apps you want.
#
# NOTE: Chrome is intentionally a Flatpak here (not RPM). Firefox instead is
# the RPM from the image: smartcard/PKCS#11 (browser-cns, firma eIDAS) does not
# work from the Firefox Flatpak sandbox.
set -euo pipefail

# Add full Flathub (proprietary apps included). Do not trust a pre-existing
# remote with the same name but a different URL.
FLATHUB_URL="https://flathub.org/repo/flathub.flatpakrepo"
REMOTE_URL="$(sudo flatpak remotes --system --columns=name,url | awk '$1 == "flathub" { print $2; exit }')"
if [ -z "$REMOTE_URL" ]; then
    sudo flatpak remote-add flathub "$FLATHUB_URL"
elif [ "$REMOTE_URL" != "$FLATHUB_URL" ]; then
    echo "Il remote di sistema flathub non punta a $FLATHUB_URL." >&2
    exit 1
fi

# >>> EDIT THIS LIST <<<
FLATPAKS=(
    com.github.jeromerobert.pdfarranger
    com.github.johnfactotum.Foliate
    com.github.xournalpp.xournalpp
    com.google.Chrome
    com.mattjakeman.ExtensionManager
    de.haeckerfelix.Shortwave
    io.github.alescdb.mailviewer
    io.gitlab.adhami3310.Converter
    org.gimp.GIMP
    org.gnome.Calendar
    org.gnome.Decibels
    org.gnome.FileRoller
    org.gnome.gThumb
    org.gnome.Loupe
    org.gnome.NautilusPreviewer
    org.gnome.Papers
    org.gnome.Showtime
    org.gnome.SoundRecorder
    org.inkscape.Inkscape
    org.libreoffice.LibreOffice
    org.qgis.qgis
)

# Custom flatpaks distributed as GitHub Releases (not on Flathub).
CUSTOM_FLATPAKS=(
    "io.github.catoblepa.PDFCropper|https://github.com/catoblepa/PDFCropper/releases/download/v0.2.0/io.github.catoblepa.PDFCropper.flatpak|8d0ca4bd8ed9e618cd29f6677f3965eb3756101b23ea29482de756d40dcc844e"
    "io.github.catoblepa.signature-viewer|https://github.com/catoblepa/signature-viewer/releases/download/v0.1.22/io.github.catoblepa.signature-viewer.flatpak|f1a449627bbfa7aa7fc5d23e3fbd6e463d112acd720448a0158657f4dc383130"
)

# Install one app at a time: a single failure must not block the others.
FAILED=()
for app in "${FLATPAKS[@]}"; do
    if sudo flatpak install --system -y --or-update flathub "$app"; then
        echo "OK: $app"
    else
        echo "FALLITO: $app" >&2
        FAILED+=("$app")
    fi
done

# Custom bundles (download + sha256 + install).
for entry in "${CUSTOM_FLATPAKS[@]}"; do
    IFS='|' read -r name url sha <<< "$entry"
    tmp="$(mktemp --suffix=.flatpak)"
    if curl -fsSL "$url" -o "$tmp" && echo "$sha  $tmp" | sha256sum -c -; then
        if sudo flatpak install --system -y --bundle "$tmp"; then
            echo "OK: $name"
        else
            echo "FALLITO: $name" >&2
            FAILED+=("$name")
        fi
    else
        echo "FALLITO (download/checksum): $name" >&2
        FAILED+=("$name")
    fi
    rm -f "$tmp"
done

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo "Installazione fallita per ${#FAILED[@]} app: ${FAILED[*]}" >&2
    exit 1
fi
