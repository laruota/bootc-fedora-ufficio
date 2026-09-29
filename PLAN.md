# bootc-fedora-ufficio — piano

Immagine **bootc GNOME** per le postazioni ufficio, derivata da Fedora Silverblue.
Porta dentro l'immagine la parte **di sistema** del repo Ansible `setup-alma10`
(AlmaLinux 10) ed elimina gli hack dovuti allo stack GNOME 46 di EL10.

L'immagine resta **pubblicabile**: non contiene materiale di terze parti non
ridistribuibile. InfoCamere Sign Desktop, font Microsoft e CA eIDAS sono
applicati **day-2** dal repo Ansible privato, in aree scrivibili.

## Decisioni (confermate)

1. **InfoCamere Sign Desktop** → **day-2** (software di terze parti): installato
   in `/opt` dal repo Ansible privato, non nell'immagine.
2. **Chrome** → flatpak (in `bootstrap-flatpaks.sh`), non RPM.
3. **ISO** → sì, generata in repo (`iso/` + `make iso`).
4. **Firefox** → **RPM** (resta quello della base Silverblue): il flatpak rompe
   smartcard/PKCS#11 (browser-cns, firma eIDAS). Non fare nulla.

## Principio

- L'immagine bake solo ciò che è **di sistema, read-only, versionabile e
  ridistribuibile**: pacchetti, config in `/usr/lib`, unit systemd,
  icone/sfondi, estensioni, binari statici. Niente contenuto proprietario.
- Il materiale **non ridistribuibile** (InfoCamere, font Microsoft, CA eIDAS)
  va **day-2** in aree scrivibili (`/opt`, `/usr/local/share/fonts`,
  `/etc/pki/...`), così l'immagine resta pubblicabile.
- `/usr` è immutabile: nel day-2 non ci si scrive. Si usano `/opt`
  (→ `/var/opt`) e `/usr/local` (→ `/var/usrlocal`), più `/etc`.
- **Nessun segreto** nell'immagine (RDP creds, PBS_PASSWORD, ipa host keytab).
- **SELinux enforcing**, niente `selinux=0`.

## Split immagine / day-2

**Nell'immagine** (vedi `scripts/`):

| setup-alma10 | file | note |
|---|---|---|
| 10-alma (pacchetti/font/icone/polkit/sfondi) | `setup.sh` + `fonts.sh` | percorsi `/usr/share`; WOL e ipa-client-install restano day-2 |
| 12-gnome-extensions | `setup.sh` | → `/usr/share/gnome-shell/extensions` |
| 14-proxmox (binari) | `setup.sh` | `proxmox-backup-client`+`pxar` → `/usr/bin`; cron+secret day-2 |
| 15-smartcard | `smartcard.sh` | pcsc-lite + acsccid (repo Fedora) + polkit + enable pcscd |
| 16-remote (solo pacchetto) | `setup.sh` | `gnome-remote-desktop`; cert/credenziali/firewall day-2 |
| 17-infocameresign | — | **day-2**: software di terze parti, in `/opt` |
| 18-ca-trust | — | **day-2**: CA eIDAS in `/etc/pki/...` (evita dipendenza di rete in build) |
| 19-poppler-ocsp | — | **eliminato** (poppler Fedora già fixato) |
| 20-sync-users | `setup.sh` | script → `/usr/bin`, exclude-list → `/usr/share/bootc-ufficio`; timer `--user` day-2 |
| 21-zram | `setup.sh` | drop-in zram + sysctl; `pri=10` in fstab day-2 |
| 901-journal | `setup.sh` | `journald.conf.d` `MaxRetentionSec=7d` |

**Day-2** (resta in `setup-alma10`, portato a Fedora; **repo privato**):

- **materiale non ridistribuibile**, in aree scrivibili:
  - InfoCamere Sign Desktop + middleware Bit4id → `/opt/infocamere_sign_desktop`,
    driver CCID → dir scrivibile + `PCSCLITE_HP_DROPDIR` in `/etc/default/pcscd`;
  - font custom (incl. Microsoft) → `/usr/local/share/fonts` + `fc-cache`;
  - CA italiane (TSL AgID) → `/etc/pki/ca-trust/source/anchors` + `update-ca-trust`;
- utenti + gsettings + CUPS per-utente + sfondi per-utente + script Nautilus
  per-utente + handler `infocameresign://` + browser-cns + RDP (creds/cert/porte)
  + cron PBS + WOL + fstab swap + mount `/srv/ARCHIVIO` +
  `ipa-client-install`/automount + flatpak override per-utente.

**Eliminati passando a Fedora**: poppler-ocsp-fix, Sushi pinnato 46 (si usa
Flathub), Papers/Loupe rimossi (restano nativi), gnome-backgrounds da EL9.

## Struttura

```
Containerfile  Makefile  README.md  PLAN.md  LICENSE  .gitignore
.github/workflows/build.yml
scripts/   setup.sh  fonts.sh  smartcard.sh
           bootstrap-flatpaks.sh  bootstrap-python.sh  push.sh
files/     icons.tar.gz  backgrounds/  gnome-extensions/  sync-users/
           75-fix-msfonts.conf  application-pkcs7-mime.svg
iso/       Containerfile  iso.yaml  interactive-defaults.ks
```

## TODO / verificare alla prima build

- [x] nomi pacchetti Fedora esatti (`papers-nautilus`, `papers-thumbnailer`, estensioni GNOME): build ok.
- [x] COPR non serve più: `pcsc-lite-acsccid` è nei repo Fedora (1.1.13-4.fc45).
- [x] Immagine ripulita dal materiale non ridistribuibile (InfoCamere, font Microsoft, CA) → spostato al day-2; l'immagine è pubblicabile.
- [ ] Day-2 (repo Ansible): driver CCID Bit4id + `PCSCLITE_HP_DROPDIR`; font in `/usr/local/share/fonts`; CA in `/etc/pki`.
- [ ] zram: Fedora ha già `zram-generator-defaults`; il drop-in deve sovrascrivere, non duplicare (da verificare a runtime in VM).
- [x] proxmox client versione `3.4.6-1` + sha256: verificato in build.
- [x] ISO: `make iso` ok (installer minimale da `fedora-silverblue:45`, label `BOOTC_UFFICIO` ≤16 char per Joliet; il payload ufficio è pullato dal registry a install-time).
