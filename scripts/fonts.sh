#!/usr/bin/env bash
# Remove unneeded international fonts / language packs.
# Keeps the core font set (Latin, GNOME UI, emoji, math/symbols) plus it/en.
# Validate in a VM before relying on this.
set -euo pipefail

# Remove only packages installed in the base. Querying names rather than NEVRAs
# avoids depending on whether dnf prints an epoch in its output.
remove_installed() {
    local package
    local -a installed=()

    for package in "$@"; do
        if dnf5 repoquery --installed --queryformat '%{name}\n' "$package" 2>/dev/null \
            | grep -Fxq "$package"; then
            installed+=("$package")
        fi
    done

    if [ "${#installed[@]}" -gt 0 ]; then
        dnf5 remove -y "${installed[@]}"
    fi
}

# --- 1. Drop language packs we don't use --------------------------------------
# langpacks-* pulls per-locale fonts, dictionaries and GUI applications.
# Keep Italian and English (including their core-/fonts- sub-packages).
mapfile -t REMOVE < <(
    dnf5 repoquery --installed --queryformat '%{name}\n' 'langpacks-*' 2>/dev/null \
        | grep -vE '^langpacks-(core-)?(fonts-)?(it|en)$' \
        | sort -u || true
)
remove_installed "${REMOVE[@]}"

# --- 2. Compute everything to drop from the default font set -------------------
# Fedora ships per-script fonts through metapackages:
#   default-fonts-cjk-*   -> Chinese / Japanese / Korean
#   default-fonts-other-* -> Arabic, Hebrew, Bengali, Devanagari, Thai, ...
#   default-fonts-<cc>    -> per-locale fonts (ur, my, si, bo, hi, fa, ...)
# The core set (Latin, GNOME, emoji, math/symbols) is kept.

# a) default-fonts metapackages, except the core-* ones
mapfile -t REMOVE < <(
    dnf5 repoquery --installed --queryformat '%{name}\n' 'default-fonts-*' 2>/dev/null \
        | grep '^default-fonts-' | grep -v '^default-fonts-core-' \
        | sort -u || true
)

# b) every google-noto-* font except the core Latin / symbols / math / emoji set.
#    google-noto-fonts-common MUST stay: it is shared data required by every
#    Noto font we keep (removing it cascades into fontconfig and breaks the OS).
KEEP='^(google-noto-fonts-common|google-noto-(sans|serif|sans-mono)(-vf)?-fonts|google-noto-sans-symbols-2-fonts|google-noto-sans-symbols-vf-fonts|google-noto-sans-math-fonts|google-noto-(color-)?emoji-fonts)$'
mapfile -t NOTO_REMOVE < <(
    dnf5 repoquery --installed --queryformat '%{name}\n' 'google-noto-*' 2>/dev/null \
        | grep -vE "$KEEP" | sort -u || true
)
REMOVE+=("${NOTO_REMOVE[@]}")

# c) other script fonts pulled in by the metapackages above or orphaned
REMOVE+=(
    paktype-naskh-basic-fonts
    sil-abyssinica-fonts sil-nuosu-fonts sil-padauk-fonts
    smc-meera-fonts
    thai-scalable-fonts-common thai-scalable-waree-fonts
    jomolhari-fonts khmer-os-system-fonts
    lohit-assamese-fonts lohit-bengali-fonts lohit-devanagari-fonts
    lohit-gujarati-fonts lohit-kannada-fonts lohit-odia-fonts
    rit-rachana-fonts madan-fonts
    pt-sans-fonts
)

# d) remove everything at once so cross-dependencies resolve cleanly
mapfile -t REMOVE < <(printf '%s\n' "${REMOVE[@]}" | sort -u)
remove_installed "${REMOVE[@]}"

# DNF and desktop helpers leave runtime state behind during the compose. It must
# not become persistent /var content in the bootc image.
rm -rf /run/dnf /tmp/nvim.root /var/cache/ibus/bus /var/lib/dnf
