# Custom GNOME bootc image for the office (bootc-fedora-ufficio).
# Derived from Fedora Silverblue; adds the SYSTEM office layer: smartcard/CNS
# packages, backup scripts, Proxmox client, icons/backgrounds, GNOME extensions.
# Chrome is a Flatpak (see scripts/bootstrap-flatpaks.sh), Firefox stays RPM.
#
# Deliberately NOT baked here (kept out of the publishable image; applied day-2
# by the private Ansible repo in writable locations):
#   - InfoCamere Sign Desktop (+ Bit4id middleware) -> /opt (day-2)
#   - Microsoft fonts                              -> /usr/local/share/fonts (day-2)
#   - Italian eIDAS CAs                            -> /etc/pki/... (day-2)
#
# Bump Fedora: change FEDORA_VERSION below (used by make build/push); also update
# the default TAG in scripts/push.sh and the tag in iso/interactive-defaults.ks.
# Build: podman build --build-arg FEDORA_VERSION=45 -t localhost/bootc-fedora-ufficio:latest .

ARG FEDORA_VERSION=45
FROM quay.io/fedora/fedora-silverblue:${FEDORA_VERSION}

# Build metadata (VERSION/SOURCE_COMMIT are passed by CI or the Makefile).
ARG VERSION=dev
ARG SOURCE_COMMIT=""

LABEL org.opencontainers.image.title="bootc-fedora-ufficio" \
      org.opencontainers.image.description="Custom GNOME bootc image for the office based on Fedora Silverblue" \
      org.opencontainers.image.source="https://github.com/catoblepa/bootc-fedora-ufficio" \
      org.opencontainers.image.vendor="catoblepa" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${SOURCE_COMMIT}" \
      org.opencontainers.image.licenses="GPL-3.0-only"

# NOTE: the RUN steps below are separate layers on purpose, so a change to one
# script only invalidates that layer during development. Each layer mounts the
# dnf5 caches and a tmpfs for /var/log. The scripts/files are BIND-MOUNTED into
# each RUN (--mount=type=bind), so no build-context leftovers end up in the image.

# Base system: packages, icons/backgrounds, polkit, GNOME extensions,
# zram, journald, backup scripts, Proxmox backup client (see scripts/setup.sh).
RUN --mount=type=bind,source=scripts,target=/tmp/scripts \
    --mount=type=bind,source=files,target=/tmp/files \
    --mount=type=cache,destination=/var/cache/libdnf5 \
    --mount=type=cache,destination=/var/lib/dnf5 \
    --mount=type=tmpfs,destination=/var/log \
    bash /tmp/scripts/setup.sh

# Trim unneeded international fonts (see scripts/fonts.sh)
RUN --mount=type=bind,source=scripts,target=/tmp/scripts \
    --mount=type=cache,destination=/var/cache/libdnf5 \
    --mount=type=cache,destination=/var/lib/dnf5 \
    --mount=type=tmpfs,destination=/var/log \
    bash /tmp/scripts/fonts.sh

# Smartcard CNS: pcsc-lite + ACS CCID, opensc, polkit, pcscd (see scripts/smartcard.sh)
RUN --mount=type=bind,source=scripts,target=/tmp/scripts \
    --mount=type=cache,destination=/var/cache/libdnf5 \
    --mount=type=cache,destination=/var/lib/dnf5 \
    --mount=type=tmpfs,destination=/var/log \
    bash /tmp/scripts/smartcard.sh

# Keep the bootstrap scripts in the immutable image (/usr/local is machine-local).
COPY --chmod=0755 scripts/bootstrap-flatpaks.sh scripts/bootstrap-python.sh /usr/libexec/bootc-ufficio/

# Host locale/timezone, root filesystem type and default kernel args. rhgb+quiet
# are required for the graphical LUKS passphrase prompt (see README); they are
# bootc kargs, so they apply "day 2" on existing installs via bootc upgrade.
RUN mkdir -p /usr/lib/bootc/install /usr/lib/bootc/kargs.d && \
    printf '[install.filesystem.root]\ntype = "btrfs"\n' \
    > /usr/lib/bootc/install/50-bootc-ufficio.toml && \
    printf 'kargs = ["rhgb", "quiet"]\n' \
    > /usr/lib/bootc/kargs.d/00-desktop.toml && \
    ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime && \
    printf 'LANG=it_IT.UTF-8\n' > /etc/locale.conf && \
    rm -f /var/cache/ldconfig/aux-cache

# /run, /tmp and /var are runtime-only / machine-local on bootc. Remove the
# state left by the package installs above (dnf, certmonger, sssd, ipa-client,
# selinux): it is day-2 / runtime state, recreated on the target by
# ipa-client-install, systemd-tmpfiles or the daemons themselves.
RUN rm -rf /run/dnf /run/certmonger /run/selinux-policy /run/sssd \
    && rm -rf /var/lib/certmonger /var/lib/ipa-client /var/lib/sss /var/lib/dnf \
    && rm -rf /var/cache/ibus /var/cache/krb5rcache /var/cache/ldconfig \
    && rm -rf /tmp/*

# Validate the image
RUN bootc container lint --fatal-warnings
