#!/bin/bash
nice -n 19 ionice -c3 rsync -az --delete --progress --bwlimit=2048 -e ssh --exclude-from="$HOME/.rsync-exclude.list" $HOME $USER@nas.laruota.local:/mnt/pool/misc/homes/$(hostname -s)/
