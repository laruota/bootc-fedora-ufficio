#!/bin/bash

# Script per configurare un timer di sistema per eseguire rsync giornalmente

set -e  # Esci se c'è un errore

echo "Setup systemd user timer per rsync"

echo "Creazione directory"
mkdir -p ~/.config/systemd/user
echo "Directory create"
echo

EXCLUDE_FILE="$HOME/.rsync-exclude.list"
SYSTEM_EXCLUDE_FILE="/usr/local/share/sync-users/exclude-list.txt"

if [[ ! -f "$EXCLUDE_FILE" ]]; then
	if [[ -f "$SYSTEM_EXCLUDE_FILE" ]]; then
		echo "Creazione file exclude list in $EXCLUDE_FILE da $SYSTEM_EXCLUDE_FILE"
		cp "$SYSTEM_EXCLUDE_FILE" "$EXCLUDE_FILE"
	else
		echo "Errore: $SYSTEM_EXCLUDE_FILE non trovato. Eseguire prima il playbook sync-users." >&2
		exit 1
	fi
	echo "Exclude list creata"
	echo
else
	echo "Exclude list già presente in $EXCLUDE_FILE"
	echo
fi

if [[ ! -f /usr/local/bin/rsync-backup-home.sh ]]; then
	echo "Errore: /usr/local/bin/rsync-backup-home.sh non trovato." >&2
	echo "Eseguire prima il playbook sync-users (20-sync-users.yml)." >&2
	exit 1
else
	echo "Script rsync di sistema trovato"
	echo
fi

echo "Creazione service"
cat > ~/.config/systemd/user/rsync-backup.service << 'SERVICE_EOF'
[Unit]
Description=Daily rsync backup to NAS
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/rsync-backup-home.sh
StandardOutput=journal
StandardError=journal
SERVICE_EOF

echo "Service creato"
echo

BACKUP_MIN=$(printf '%02d' "$(( 16#$(hostname -s | md5sum | cut -c1-8) % 30 ))")

echo "Creazione timer"
cat > ~/.config/systemd/user/rsync-backup.timer << TIMER_EOF
[Unit]
Description=Daily rsync backup timer

[Timer]
OnCalendar=*-*-* 17:${BACKUP_MIN}
Persistent=true
Unit=rsync-backup.service

[Install]
WantedBy=timers.target
TIMER_EOF

echo "Timer creato"
echo

echo "Abilitazione timer"
systemctl --user daemon-reload
systemctl --user enable rsync-backup.timer
systemctl --user start rsync-backup.timer
echo "Timer abilitato"
echo
