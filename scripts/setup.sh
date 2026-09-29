#!/usr/bin/env bash
# Base system setup for the bootc-fedora-ufficio image.
# Runs inside the container build (files are bind-mounted at /tmp/files).
# Extend the lists below to customize.
set -euo pipefail

# --- Install packages --------------------------------------------------------
# install_weak_deps=False: no Recommends dragged in. Nomi Fedora; verificare
# papers-nautilus / papers-thumbnailer alla prima build (su EL10 si chiamano cosi).
dnf5 install -y --setopt=install_weak_deps=False \
    dconf-editor \
    gnome-tweaks \
    seahorse \
    fuse \
    zenity \
    qpdf \
    poppler-utils \
    ghostscript \
    GraphicsMagick \
    gnome-shell-extension-appindicator \
    gnome-shell-extension-caffeine \
    gnome-shell-extension-dash-to-dock \
    gnome-shell-extension-apps-menu \
    gnome-shell-extension-places-menu \
    freeipa-client \
    papers-nautilus \
    papers-thumbnailer \
    libnotify \
    cups-client \
    gnome-text-editor \
    python3-pip \
    python3-pandas \
    python3-openpyxl \
    python3-gobject \
    pipx \
    zram-generator \
    gnome-remote-desktop \
    rsync \
    unzip \
    binutils

# --- Remove unneeded packages (only the ones actually present) ---------------
REMOVE=(
    gnome-clocks gnome-tour
    ibus-anthy ibus-hangul ibus-m17n ibus-typing-booster ibus-libpinyin ibus-libzhuyin
    NetworkManager-adsl NetworkManager-team
    evolution-ews
    gnome-shell-extension-background-logo
)
INSTALLED=()
for p in "${REMOVE[@]}"; do
    if dnf5 repoquery --installed --queryformat '%{name}\n' "$p" 2>/dev/null | grep -Fxq "$p"; then
        INSTALLED+=("$p")
    fi
done
if [ "${#INSTALLED[@]}" -gt 0 ]; then
    dnf5 remove -y "${INSTALLED[@]}"
    dnf5 autoremove -y || true
fi

# --- Icons and backgrounds (to /usr/share, NOT /usr/local) ------------------
# NOTE: custom fonts are NOT baked into the image (the collection includes
# Microsoft fonts): they are applied day-2 in /usr/local/share/fonts. Here the
# image ships only the Fedora font packages (see scripts/fonts.sh).
mkdir -p /usr/share/icons /usr/share/backgrounds
# --no-same-owner: i tarball hanno uid/gid dell'host; nel container rootless
# non sono mappati e tar fallirebbe il chown. In /usr/share serve root:root.
tar --no-same-owner -xzf /tmp/files/icons.tar.gz -C /usr/share/
chmod -R a+rX /usr/share/icons
cp /tmp/files/backgrounds/*.svg /usr/share/backgrounds/
mkdir -p /usr/share/icons/Adwaita/scalable/mimetypes
cp /tmp/files/application-pkcs7-mime.svg /usr/share/icons/Adwaita/scalable/mimetypes/application-pkcs7-mime.svg

# fontconfig: MS fonts substitution (system-wide)
mkdir -p /usr/share/fontconfig/conf.avail /usr/share/fontconfig/conf.d
cp /tmp/files/75-fix-msfonts.conf /usr/share/fontconfig/conf.avail/75-fix-msfonts.conf
ln -sf ../conf.avail/75-fix-msfonts.conf /usr/share/fontconfig/conf.d/75-fix-msfonts.conf

# --- Polkit rule: allow reboot without authentication ------------------------
mkdir -p /usr/share/polkit-1/rules.d
cat > /usr/share/polkit-1/rules.d/50-allow-reboot.rules <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.login1.reboot") {
        return polkit.Result.YES;
    }
});
EOF

# --- GNOME shell extensions (zips -> /usr/share/gnome-shell/extensions/<uuid>) -
mkdir -p /usr/share/gnome-shell/extensions
for z in /tmp/files/gnome-extensions/*.zip; do
    d="$(mktemp -d)"
    unzip -q "$z" -d "$d"
    uuid="$(grep -oP '"uuid"\s*:\s*"\K[^"]+' "$d/metadata.json" | head -n1)"
    [ -n "$uuid" ] || { echo "uuid non trovato in $z" >&2; exit 1; }
    mkdir -p "/usr/share/gnome-shell/extensions/$uuid"
    cp -a "$d"/. "/usr/share/gnome-shell/extensions/$uuid/"
    rm -rf "$d"
done
chmod -R a+rX /usr/share/gnome-shell/extensions

# --- ZRAM swap --------------------------------------------------------------
# Drop-in: sovrascrive l'eventuale default di zram-generator-defaults di Fedora.
mkdir -p /etc/systemd/zram-generator.conf.d
cat > /etc/systemd/zram-generator.conf.d/10-zram.conf <<'EOF'
[zram0]
zram-size = min(ram, 8192)
compression-algorithm = zstd
swap-priority = 100
EOF
mkdir -p /usr/lib/sysctl.d
printf 'vm.swappiness = 100\n' > /usr/lib/sysctl.d/99-zram.conf

# --- Journald retention (7 days) ---------------------------------------------
mkdir -p /usr/lib/systemd/journald.conf.d
printf '[Journal]\nMaxRetentionSec=7d\n' > /usr/lib/systemd/journald.conf.d/50-retention.conf

# --- sshd enabled (le postazioni sono gestite via Ansible/SSH) ---------------
systemctl enable sshd.service

# --- Backup scripts (sync-users) ---------------------------------------------
# Originali in /usr/local (machine-local): qui in /usr (versionati).
install -m0755 /tmp/files/sync-users/rsync-backup-home.sh      /usr/bin/rsync-backup-home.sh
install -m0755 /tmp/files/sync-users/ripristina-backup-home.sh /usr/bin/ripristina-backup-home.sh
mkdir -p /usr/share/bootc-ufficio
install -m0644 /tmp/files/sync-users/exclude-list.txt          /usr/share/bootc-ufficio/exclude-list.txt
sed -e 's#/usr/local/share/sync-users/exclude-list.txt#/usr/share/bootc-ufficio/exclude-list.txt#g' \
    -e 's#/usr/local/bin/rsync-backup-home.sh#/usr/bin/rsync-backup-home.sh#g' \
    /tmp/files/sync-users/setup-rsync-timer-backup-home.sh > /usr/bin/setup-rsync-timer-backup-home.sh
chmod 0755 /usr/bin/setup-rsync-timer-backup-home.sh
mkdir -p /usr/share/applications
sed 's#Exec=/usr/local/bin/ripristina-backup-home.sh#Exec=/usr/bin/ripristina-backup-home.sh#' \
    /tmp/files/sync-users/ripristina-backup-home.desktop > /usr/share/applications/ripristina-backup-home.desktop

# --- Proxmox Backup Client (binario statico ufficiale) -----------------------
# Version/checksum pinnate (vedi indice download.proxmox.com). Il cron con le
# credenziali resta day-2 (segreti).
PBS_VER="3.4.6-1"
PBS_SHA="9802265b07e0b9efa6b25ca0a5db6ff132447698a4f81cdc7448726b578a4e30"
PBS_DEB="proxmox-backup-client-static_${PBS_VER}_amd64.deb"
PBS_URL="http://download.proxmox.com/debian/pbs-client/dists/bookworm/main/binary-amd64/${PBS_DEB}"
tmp="$(mktemp -d)"
curl -fsSL "$PBS_URL" -o "$tmp/$PBS_DEB"
echo "$PBS_SHA  $tmp/$PBS_DEB" | sha256sum -c -
( cd "$tmp" && ar x "$PBS_DEB" && mkdir -p ex && tar -xf data.tar.* -C ex )
install -m0755 "$tmp/ex/usr/bin/proxmox-backup-client" /usr/bin/proxmox-backup-client
install -m0755 "$tmp/ex/usr/bin/pxar"                  /usr/bin/pxar
rm -rf "$tmp"

# Refresh the font cache built during the compose (must not persist /var state)
fc-cache -f
rm -rf /run/dnf /tmp/nvim.root /var/cache/ibus/bus /var/lib/dnf
