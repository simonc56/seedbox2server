#!/bin/sh
#
# ce fichier est sur la seedbox et est exec a chaque fin de dl
# .rtorrent.rc doit contenir la ligne suivante :
# method.set_key = event.download.finished,notif,"execute2={/home/***/notify.sh,$d.hash=,$d.base_path=}"
# cree un historique des dl sur la seedbox et notifie chaque dl
# historique utilise ensuite par recup.sh en local
# les fichiers doivent se telecharger dans une arborescence /blabla/<label>/<torrent_name>/

histo="/home/***/.histo"
WEBHOOK_URL="https://hooks.slack.com/services/******"
maison="http://kodi_servername:****"

if [ "$#" -lt 1 ] 
then
   echo "Need input"
   echo "Exiting..."
   exit 1
fi

# Load vars.
HASH=$1
shift

FROM="$@"

#enleve le slash de fin
FROM="${FROM%/}"

#prend tout apres dernier slash
NAME=${FROM##*/}

# ecriture fichier histo.hst
now="$(date +%Y.%m.%d-%Hh%Mm%S)"
echo $FROM > "$histo/$now.hst"

# parametres slack
botname="seedbox"
boticon=":cloud:"
text="\`$NAME\` est dans la seedbox."
botname="\"username\":\"$botname\","
boticon="\"icon_emoji\":\"$boticon\","
payload="payload={$boticon$botname\"text\":\"$text\"}"

#slack
#/usr/bin/curl -s --data-urlencode "$payload" "$WEBHOOK_URL" 2>&1

#maison
/usr/bin/curl -G -s --data-urlencode "nom=$NAME" "$maison" 2>&1
