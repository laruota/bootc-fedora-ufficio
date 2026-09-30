# bootc-fedora-ufficio

Immagine **bootc GNOME** per le postazioni ufficio, derivata da Fedora Silverblue.
Porta nell'immagine la parte **di sistema** del setup Ansible `setup-alma10`
(pacchetti, smartcard CNS, icone/sfondi, estensioni GNOME, backup, Proxmox
client) ed elimina gli hack dovuti allo stack GNOME 46 di EL10 (poppler OCSP,
Sushi pinnato, Papers/Loupe vecchi, sfondi EL9).

L'immagine **non** contiene materiale di terze parti non ridistribuibile:
InfoCamere Sign Desktop, font Microsoft e CA eIDAS sono applicati **day-2** dal
repo Ansible privato, in aree scrivibili. Così l'immagine resta pubblicabile.

Vedi [PLAN.md](PLAN.md) per il piano completo e la mappatura playbook → immagine.

## Decisioni

- **Chrome** = Flatpak (`bootstrap-flatpaks.sh`).
- **Firefox** = RPM (dalla base): il flatpak rompe smartcard/PKCS#11 (browser-cns, firma).
- **InfoCamere Sign Desktop** = **day-2** (software di terze parti, in `/opt`).
- **SELinux** enforcing, niente `selinux=0`.
- **sshd** abilitato (le postazioni sono gestite via Ansible/SSH).

## Immagine vs day-2

**Nell'immagine (sistema, immutabile, pubblicabile):** pacchetti ufficio,
smartcard CNS, icone/sfondi, estensioni GNOME, zram, journald 7d, backup
scripts, Proxmox client, polkit, kargs `rhgb quiet`.

**Day-2 (repo Ansible `setup-alma10` privato, portato a Fedora):**
- materiale non ridistribuibile in aree scrivibili: InfoCamere (+ Bit4id) →
  `/opt`; font Microsoft → `/usr/local/share/fonts`; CA eIDAS → `/etc/pki/...`;
- utenti + gsettings + CUPS per-utente + sfondi per-utente + script Nautilus
  per-utente + handler `infocameresign://` + browser-cns + RDP
  (credenziali/cert/porte) + cron PBS (segreti) + WOL + fstab swap + mount
  `/srv/ARCHIVIO` + `ipa-client-install`/automount + override flatpak per-utente.

## Build

    make build                       # usa FEDORA_VERSION=45 di default
    make shellcheck                  # lint degli script shell
    make smoke                       # test del contenuto senza VM

## Test in VM

    sudo dnf install bcvk
    bcvk ephemeral run-ssh localhost/bootc-fedora-ufficio

(sshd è abilitato di default in questa immagine.)

## Pubblicazione su ghcr.io

La GitHub Action `.github/workflows/build.yml` builda e pubblica su
`ghcr.io/laruota/bootc-fedora-ufficio:<FEDORA_VERSION>` e `:latest` a ogni push
su `main` (e su `workflow_dispatch`). Tag mutabili. Il package deve essere
**pubblico** per il pull anonimo del deploy.

    make push ORG=laruota
    podman pull ghcr.io/laruota/bootc-fedora-ufficio:45

## ISO (installazione)

`make installer` costruisce il container installer; `make iso` genera l'ISO con
`image-builder` (`bootc-generic-iso`) in `output/`. L'ISO installa
`ghcr.io/laruota/bootc-fedora-ufficio:45` (vedi `iso/interactive-defaults.ks`).

    make installer
    make iso

## Aggiornamenti sulla target

    bootc switch ghcr.io/laruota/bootc-fedora-ufficio:45
    bootc upgrade

## Prompt grafico LUKS e SELinux

L'immagine imposta `rhgb quiet` in `/usr/lib/bootc/kargs.d/00-desktop.toml`
(prompt grafico della passphrase LUKS; senza `rhgb` plymouth resta in testo).
Su un sistema già installato:

    sudo rpm-ostree kargs --append=rhgb --append=quiet

⚠️ **SELinux**: il live environment dell'ISO parte in **permissive**
(`enforcing=0` in `iso/iso.yaml`): lo squashfs non è etichettato per il live e
sotto enforcing systemd si blocca. NON si usa `selinux=0` perché disabiliterebbe
SELinux sul target. Dopo l'installazione verificare il target:

    getenforce        # atteso: Enforcing

## Licenza

GPL-3.0 — vedi [LICENSE](LICENSE).
