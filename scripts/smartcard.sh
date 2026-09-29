#!/usr/bin/env bash
# Smartcard CNS support: pcsc-lite + ACS CCID driver (pcsc-lite-acsccid, ora nei
# repo Fedora ufficiali: 1.1.13-4.fc45), opensc, polkit rule, pcscd enabled.
set -euo pipefail

dnf5 install -y --setopt=install_weak_deps=False \
    pcsc-lite \
    pcsc-lite-libs \
    pcsc-lite-ccid \
    pcsc-lite-acsccid \
    opensc

# Polkit rule: allow local users to access the card/reader.
mkdir -p /usr/share/polkit-1/rules.d
cat > /usr/share/polkit-1/rules.d/10-pcscd.rules <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.debian.pcsc-lite.access_pcsc" ||
        action.id == "org.debian.pcsc-lite.access_card") {
        return polkit.Result.YES;
    }
});
EOF

# pcscd via socket activation (Fedora default). Enabling the socket is enough.
systemctl enable pcscd.socket
