#!/bin/sh
# 1.4
# todo : credentials ftp dans ~/.netrc
# fetch files from seedbox ftp server, lftp is required
# remote seedbox files must be downloaded in a path like this :
# /some/path/torrents/<label>/<torrent_name>/
# with specific sort using labels 'movies' and 'tv' to correctly allocate them later
# this script can be run either on demand or periodically with cron
# on demand it is triggered by listener.sh which is waiting calls from seedbox notify.sh
# how it works: movies are moved to a movie folder. Tv shows are not moved the same way, a http request is sent to medusa which will move them into its library
# if there is dl error, go read fetcher.log and .histo contents

# extensions in .histo folder :
# hst     = torrent to be fetched
# hstok   = torrent successfully fetched
# hsterr  = torrent error (lftp error during fetch)
# -> folder /tmp/.histo  = fetches queue, used when script is already running
# filename ex. : SeedboxName_2019.11.02-13h18m29_1249CF912953450897D3149DB56DF5E1431E48D1.hst

# IMPORTANT VARIABLES :
CONFIG="/home/config.yml"
BASE_STORE="/media/tera/downloads" #where to put files fetched by lftp (not their final place)
MOVIES_DIR="/media/tera/films/" #final destination of your movies
histo='torrents/lecture' #in which remote folder is .histo (because some seedboxes forbid to write on ftp root)
histo_local="$HOME" #in which local folder is .histo
LOCK="$histo_local"/fetcher.lock
LOG="$histo_local"/fetcher.log
b2="$histo_local"/.batch-dl   # dl batch of torrent files
EXTENSIONS="mkv,avi,mp4,m4v,iso,mpg,ts,srt"
no_space=0 # option to replace spaces by . in movies and tv filenames

# Variables read in config file (each yaml indent is replaced by _):
# seedbox_usr, seedbox_pwd
# seedbox_ftp_host="ftp://serv.seedbox.com:21"
# seedbox_ftp_root="/home/me/"
# slack_hook_url, telegram_token, telegram_chat_id,...

function parse_yaml {
   local prefix=$2
   local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
   sed -ne "s|^\($s\):|\1|" \
        -e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
        -e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
   awk -F$fs '{
      indent = length($1)/2;
      vname[indent] = $2;
      for (i in vname) {if (i > indent) {delete vname[i]}}
      if (length($3) > 0) {
         vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
         printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
      }
   }'
}
eval $(parse_yaml "$CONFIG")
who=$1 # name of calling seedbox
who_ftp_host=\$"$who"_ftp_host ; who_ftp_host=$(eval echo $who_ftp_host)
who_usr=\$"$who"_usr ; who_usr=$(eval echo $who_usr)
who_pwd=\$"$who"_pwd ; who_pwd=$(eval echo $who_pwd)
now="$(date +%d.%m.%Y-%Hh%Mm%S)"
hour="$(date +%Hh%Mm%S)"
echo "-----------" $now "-----------" >> "$LOG"

# check if script already runs
if [ -f "$LOCK" ] && [ ! -z "$who_usr" ] ; then
  # YES : we store as tmp and exit
  mkdir -p "$histo_local"/tmp/.histo
  echo "Previous fetch not finished yet, we store in .tmp"
  # fetch histo files in temp
  sleep 5 # wait that previous script deletes its .hst
  lftp -u $who_usr,$who_pwd $who_ftp_host <<EOF
mget -O "$histo_local/tmp/.histo" "$histo/.histo/*.hst"
mrm -f "$histo/.histo/*.hst"
exit
EOF
  echo "and leave..."
  exit 0
elif [ -f "$LOCK" ] && [ -z "$who_usr" ] ; then #no seedbox in args
  echo "Previous fetch not finished yet, exit"
  exit 0
fi
# NO : we lock
touch "$LOCK"
mkdir -p "$histo_local"/.histo
if [ ! -z "$who_usr" ] ; then
  #if we have a seedbox name in argument
  #Check lftp config. At startup lftp reads /etc/lftp.conf then ~/.lftprc then ~/.lftp/rc
  if [ ! -f "$HOME/.lftprc" ] ; then
    echo "No custom config file for lftp, we create it here: ~/.lftprc" >> "$LOG"
    echo '# lftp configuration file created by fetcher.sh on' $now > "$HOME/.lftprc"
    echo 'set ftp:ssl-force true' >> "$HOME/.lftprc"  #force encrypted password (not the data)
    echo 'set ftps:initial-prot C' >> "$HOME/.lftprc" #Data Connection Security, see RFC4217 section 9 (Clear=no encr. and no auth.)
    echo 'set sftp:auto-confirm yes' >> "$HOME/.lftprc" #Automatically accept remote server public key (stored in .ssh/known_hosts)
    echo 'set ssl:verify-certificate false' >> "$HOME/.lftprc"
  fi
  # then we fetch histo files
  echo "Fetching .hst files"
  lftp -u $who_usr,$who_pwd $who_ftp_host <<EOF
mget -O "$histo_local/.histo" "$histo/.histo/*.hst"
mrm -f "$histo/.histo/*.hst"
exit
EOF
else
  #no seedbox name, we check if there are local .hst
  for file in "$histo_local"/.histo/* ; do
    if [ ! -f $file ] ; then
      # no file, we leave
      rm "$LOCK"
      echo "No .hst, no seedbox to call : exit..."
      exit 0
    fi
    hstname=${file##*/}
    who=${hstname%_*}
    who=${who%_*} #in 2 steps to allow a 'who' with _
  done
fi

touch "$LOCK"
nb_kodi=0
while true ; do
  nb=0
  # preparation of torrents fetching batch
  # setting up credentials
  who_ftp_host=\$"$who"_ftp_host ; who_ftp_host=$(eval echo $who_ftp_host)
  who_usr=\$"$who"_usr ; who_usr=$(eval echo $who_usr)
  who_pwd=\$"$who"_pwd ; who_pwd=$(eval echo $who_pwd)
  who_ftp_root=\$"$who"_ftp_root ; who_ftp_root=$(eval echo $who_ftp_root)
  echo 'open -u' $who_usr','$who_pwd $who_ftp_host > $b2
  echo 'lcd' $BASE_STORE >> $b2
  for file in "$histo_local"/.histo/"$who"_*.hst ; do
    # if nothing to fetch we leave
    if [ ! -f "$file" ] ; then
      echo "Nothing to fetch, exit..."
      rm "$LOCK"
      exit 0
    fi
    nb=$((nb+1))
    fol=$(cat $file)
    fol="${fol%/}"
    NAME=${fol##*/}
    FULLDIR=${fol%/*}
    DIR=${FULLDIR##*/}
    FULLDIR=${FULLDIR#$who_ftp_root}
    STORE="$BASE_STORE"
    if [ "$DIR" != "torrents" ] ; then
      STORE="$STORE/$DIR"
    fi
    #escape all special caracters for the -i of mirror
    SPEC_NAME=$(echo "$NAME" | sed 's/[^[:alnum:]]/\\&/g')
    echo "mirror -x .* -x .*/ -i '$SPEC_NAME' '$FULLDIR' '$STORE'" >> $b2
    # Notify slack or telegram
    text="$NAME"
    botname="\\\"username\\\":\\\"$slack_botname\\\","
    boticon="\\\"icon_emoji\\\":\\\"$slack_boticon\\\","
    payload="payload={$boticon$botname\\\"text\\\":\\\"$text\\\"}"
    if [ $notif_slack == 1 ] ; then
      echo "!curl -s --data-urlencode \"$payload\" \"$slack_hook_url\" > /dev/null 2>> \"$LOG\"" >> $b2
    fi
    if [ $notif_telegram == 1 ] ; then
      echo "!curl -s -X POST https://api.telegram.org/bot$telegram_token/sendMessage -d chat_id=$telegram_chat_id -d text=\"$text\" > /dev/null 2>> \"$LOG\"" >> $b2
    fi
    #not removing hst because next loop would not work, rename it as .hstok
    echo "!mv \"$file\" \"${file}ok\"" >> $b2
    if [ "$DIR" == "movies" ] || [ "$DIR" == "tv" ] ; then
      # Notify kodi as downloads progress
      echo "!kodi-send -a \"Notification(New,$NAME,10000)\"" >> $b2
    fi
  done
  echo 'exit' >> $b2

  hour="$(date +%Hh%Mm%S)"
  echo "$hour ---> trying to fetch $nb torrent-s on $who" >> "$LOG"
  #batch ready, launching fetch, wait...
  sleep 3 # wait last cmd_ftp deconnexion
  lftp -f $b2
  
  #check if dl error
  hour="$(date +%Hh%Mm%S)"
  for file in "$histo_local"/.histo/"$who"-*.hst ; do
    # if no files from this seedbox, all is ok no error occured
    if [ ! -f $file ] ; then
      echo "$hour ---> transfer from $who successfully done" >> "$LOG"
    else
      fol=$(cat $file)
      guilty=${fol##*/}
      #hst_file=${file##*/} v1.2.0: to remove
      mv "$file" "$file"err
      echo "$hour ---> $who : stopped transfer" >> "$LOG"
      if [ $notif_slack == 1 ] ; then
        curl -s --data-urlencode "payload={\"icon_emoji\":\":heavy_exclamation_mark:\",\"username\":\"Error\",\"text\":\"$guilty ($who)\"}" "$slack_hook_url" > /dev/null 2>&1
      fi
      if [ $notif_telegram == 1 ] ; then
        curl -s -X POST https://api.telegram.org/bot$telegram_token/sendMessage -d chat_id=$telegram_chat_id -d text="Error: $guilty ($who)" > /dev/null 2>&1
      fi
      break # error only on first remaining .hst
    fi
  done

  # at this stage everything is fetched locally, except if lftp failed somewhere
  # notify Medusa if tv label and allocate files in correct folders according to label 'movies' or 'tv'
  for file in "$histo_local"/.histo/*.hstok ; do
    if [ ! -f $file ] ; then
      break
    fi
    HASH=${file##*_}
    HASH=${HASH%.*}
    fol=$(cat $file)
    #echo "fol=$fol" >> "$LOG"
    fol="${fol%/}"
    NAME=${fol##*/}
    DIR=${fol%/*}
    DIR=${DIR##*/}
    #DIR is maybe "torrents"
    STORE="$BASE_STORE/$DIR"
    #for information, we log torrent size
    tor_size=$(du -sch "$STORE/$NAME" | awk 'END{print $1}')
    echo "$tor_size : $NAME" >> "$LOG"
    # Postprocessing to Medusa if tv and copy if movie
    if [ "$DIR" == "tv" ] ; then
      nb_kodi=$((nb_kodi+1))
      # if torrent is a folder
      if [ -d "$STORE/$NAME" ] ; then
        STORE="$STORE/$NAME"
      fi
      # send to medusa which will do a 'move'
      NAME=${fol##*/}
      # map docker path if needed then use it in curl command
      #docker_fold="/tv${STORE#'/media/tera'}"
      echo "curl:" "nzbName=$NAME&proc_dir=$STORE&proc_type=manual"
      curl -G -s -S --data-urlencode "nzbName=$NAME" \
                    --data-urlencode "proc_dir=$STORE" \
                    --data-urlencode "proc_type=manual" \
                    --data-urlencode "quiet=1" \
                    http://localhost:18081/medusa/home/postprocess/processEpisode 2>&1
      #if [ $? -eq 0 ] && [ "$STORE" != "$BASE_STORE/tv" ] ; then
        # if curl send to medusa is success, we remove the folder
        #rm -r "$STORE"
      #fi
    elif [ "$DIR" == "movies" ] ; then
      nb_kodi=$((nb_kodi+1))
      #move only movie and subtitles
      for file in "$STORE/$NAME"/* ; do
        #remove ending /* if torrent is a single file
        file="${file%/\*}"
        name=${file##*/}
        path=${file%/*}'/'
        ext=${file##*.}
        #echo "movie file=$file" >> "$LOG"
        if [ "${EXTENSIONS/$ext}" != "$EXTENSIONS" ] && [ -f "$file" ] && [ "${name%.*}" != "sample" ] ; then
          # MOVE the file
          #echo "movie  ok=$file" >> "$LOG"
          #goodname="${name// /.}"
          goodname=$(echo "$name" | sed 's/  */\./g')
          if [ $no_space == 1 ] && [ "$name" != "$goodname" ] ; then
            #remove ([.-.
            goodname=${goodname//[\(\)\[\]]/}
            goodname=${goodname//.-./.}
            goodname=$(echo $goodname | tr -s '.')
            goodname=${goodname#.}
            goodname_file="${path}${goodname}"
            mv "$file" "${goodname_file}"
          else
            goodname_file="${path}${name}"
            goodname="${name}"
          fi
          mv "${goodname_file}" "${MOVIES_DIR}"
        fi
      done
      #notif radarr
      python "/storage/radarr.py" "${MOVIES_DIR}${goodname}" "$HASH" >> "$LOG" 2>&1
      #remove the folder here
      #rm -r "$STORE/$NAME"
    fi
  done

  rm -f "$histo_local"/.histo/*.hstok

  # is there any other .hst files ? received in tmp during current fetch ? or a stopped transfer ?
  # if yes, .hst files are pulled out from tmp to be read
  for file in "$histo_local"/tmp/.histo/* ; do
    if [ -f $file ] ; then
      # pull out .hst from tmp
      hstname=${file##*/}
      mv "$file" "$histo_local/.histo/$hstname"
    else
      break # nothing in tmp
    fi
  done
  for file in "$histo_local"/.histo/*.hst ; do
    if [ ! -f $file ] ; then
      # no hst file remaining, it is over
      rm "$LOCK"
      if [ $nb_kodi -gt 0 ] ; then
        # Update XBMC VideoLibrarys (all dl grouped in a single update)
        sleep 2
        kodi-send -a "UpdateLibrary(video)"
        sleep 2
        #kodi-send -a "UpdateLibrary(music)"
      fi
      # check disk space, alert if less than ~9,5Go
      disq_sp=$(df /dev/sda1 | awk '{if(NR>1)print $4}')
      disq_sp_h=$(df -h /dev/sda1 | awk '{if(NR>1)print $4}')
      threshold=10000000
      if [ "$disq_sp" -lt "$threshold" ] ; then
        if [ $notif_slack == 1 ] ; then
            curl -s --data-urlencode "payload={\"icon_emoji\":\":heavy_exclamation_mark:\",\"username\":\"Attention\",\"text\":\"Disk space is low (${disq_sp_h}o)\"}" "$slack_hook_url" > /dev/null 2>&1
        fi
        if [ $notif_telegram == 1 ] ; then
            curl -s -X POST https://api.telegram.org/bot$telegram_token/sendMessage -d chat_id=$telegram_chat_id -d text="Disk Space is low (${disq_sp_h}o)" > /dev/null 2>&1
        fi
      fi
      echo "Exit..."
      exit 0
    else
      # on which seedbox (the loop will end with the 'who' of the last found .hst)
      who=${hstname%_*}
      who=${who%_*} #in 2 steps to allow a 'who' with _
    fi
  done
  # we restart to read other hst files
done
