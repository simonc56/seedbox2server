#!/bin/sh
# 1.2.0
# this script is on the seedbox and runs at each download finish
# .rtorrent.rc must have this line added :
# method.set_key = event.download.finished,notif,"execute2={/home/***/notify.sh,$d.hash=,$d.base_path=}"
# creates an history (in .histo folder) of seedbox downloads and notify home server
# history is then read by fetcher.sh
# files must be downloaded in a path like this : /somepath/<label>/<torrent_name>/

who="seedbox_name" # change this to a friendly name corresponding to one in config.yml
histo="/home/user/torrents/lecture/.histo" # choose the full path to .histo, the folder in which history of finished dl will be
home="http://servername_or_ip:port" # how to http reach your home server's listener.sh script (this is NOT ftp)

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

#removes last slash
FROM="${FROM%/}"

#take everything after last slash
NAME=${FROM##*/}

# write .hst file
now="$(date +%Y.%m.%d-%Hh%Mm%S)"
echo $FROM > "$histo/${qui}_${now}_$HASH.hst"

#call home (will trigger listener.sh)
/usr/bin/curl -G -s --data-urlencode "from=$who" \
                    --data-urlencode "name=$NAME" \
                    "$home" 2>&1
