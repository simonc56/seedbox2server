#!/bin/sh
# 1.2.0
# script qui ecoute sur le port **** et execute recup.sh
# a chaque appel de notify.sh provenant de la seedbox
# penser a ouvrir le port

RECUPLOG="/storage/recup.log"

while true
do
  nc -lk -p **** < /usr/www/index.html | while read line
    do
      match=$(echo $line | grep -c 'GET /')
      now="$(date +%d.%m.%Y-%Hh%Mm%S)"
      if [ $match -eq 1 ]; then
        #NAME=${line##*=}
        #NAME=${NAME%HTTP*}
        echo "$now NETCAT A RECU: $line" >> $RECUPLOG
        de_notif=$(echo $line | grep -c '?from=')
        if [ $de_notif -eq 1 ]; then
          #donner le nom de la seedbox en argument à recup.sh
          qui=${line%%&*}
          qui=${qui##*=}
          /storage/recup.sh "$qui" >> /storage/recup.log 2>&1 &
        fi
      fi
    done
done
