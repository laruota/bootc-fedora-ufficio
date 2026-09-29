#!/bin/bash
# Script per ripristinare backup utente da NAS tramite zenity

set -e

# Configurazione
readonly SSH_HOST="nas.laruota.local"
readonly REMOTE_BASE="/mnt/pool/misc/homes"
readonly TMP_LIST=$(mktemp)

# Trova tutti i backup disponibili per l'utente
ssh "$SSH_HOST" "find $REMOTE_BASE -maxdepth 2 -type d -name '$USER'" | \
    awk -F'/' '{print $(NF-1)}' | sort -u > "$TMP_LIST"

if [ ! -s "$TMP_LIST" ]; then
    zenity --error --text="Nessun backup trovato per l'utente $USER."
    exit 1
fi

# Costruisci lista per zenity
BACKUP_LIST=()
set +e
while read -r HOST; do
    [ -z "$HOST" ] && continue
    SYNC_DATE=$(ssh "$SSH_HOST" "stat -c '%y' $REMOTE_BASE/$HOST/$USER" 2>/dev/null < /dev/null | cut -d' ' -f1,2)
    [ -z "$SYNC_DATE" ] && SYNC_DATE="N/D"
    BACKUP_LIST+=("$HOST" "$SYNC_DATE")
done < "$TMP_LIST"
set -e

[ ${#BACKUP_LIST[@]} -eq 0 ] && zenity --error --text="Nessun backup valido trovato." && exit 1

# Selezione backup
SELECTED_HOST=$(zenity --list --title="Ripristino Backup - Utente: $USER" \
    --text="Seleziona l'host da cui ripristinare:" \
    --column="Host" --column="Data ultimo backup" "${BACKUP_LIST[@]}" \
    --height=400 --width=600)

[ -z "$SELECTED_HOST" ] && exit 0

# Conferma ripristino
zenity --question --title="Conferma Ripristino" \
    --text="Ripristinare il backup da <b>$SELECTED_HOST</b>?\n\nATTENZIONE: La home attuale verrà sovrascritta!" \
    --width=400 || { rm -f "$TMP_LIST"; exit 0; }

# Verifica password utente
USER_PASS=$(zenity --password --title="Autenticazione richiesta" \
    --text="Inserisci la tua password per procedere con il ripristino:") || { rm -f "$TMP_LIST"; exit 0; }

# Verifica la password con su (più affidabile di sudo quando sudo è senza password)
if ! su -c "true" "$USER" <<< "$USER_PASS" 2>/dev/null; then
    zenity --error --text="✗ Password non corretta. Operazione annullata."
    unset USER_PASS
    rm -f "$TMP_LIST"
    exit 1
fi
unset USER_PASS

# Esegui ripristino solo se password verificata
rsync -az --delete --progress -e ssh \
    "$SSH_HOST:$REMOTE_BASE/$SELECTED_HOST/$USER/" "$HOME/" 2>&1 | \
zenity --progress --title="Ripristino Backup" \
    --text="Ripristino da $SELECTED_HOST in corso...\n\nAttendere il completamento dell'operazione." \
    --pulsate --auto-close --no-cancel

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    zenity --info --text="✓ Ripristino completato da $SELECTED_HOST"
else
    zenity --error --text="✗ Errore durante il ripristino da $SELECTED_HOST"
    rm -f "$TMP_LIST"
    exit 1
fi

# Pulizia
rm -f "$TMP_LIST"
