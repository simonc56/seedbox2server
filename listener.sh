#!/bin/sh
# 1.2.0
# this script listen on a port you choose and executes fetcher.sh at every notify.sh call from the seedbox
# make sure you opened the port in your firewall/gateway

LOG="/storage/fetcher.log"
PORT=****

while true
do
  nc -lk -p $PORT < /usr/www/index.html | while read line
    do
      match=$(echo $line | grep -c 'GET /')
      now="$(date +%d.%m.%Y-%Hh%Mm%S)"
      if [ $match -eq 1 ]; then
        #NAME=${line##*=}
        #NAME=${NAME%HTTP*}
        echo "$now NETCAT RECEIVED: $line" >> $LOG
        from_notif=$(echo $line | grep -c '?from=')
        if [ $from_notif -eq 1 ]; then
          #gives the seedbox name as argument to fetcher.sh
          qui=${line%%&*}
          qui=${qui##*=}
          /storage/fetcher.sh "$qui" >> $LOG 2>&1 &
        fi
      fi
    done
done
