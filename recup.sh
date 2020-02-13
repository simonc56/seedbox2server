#!/bin/sh
# 1.4
# todo : credentials ftp dans ~/.netrc
# recuperation de fichiers sur serveurs ftp, il faut lftp
# les fichiers distants doivent se telecharger dans une arborescence
# /home/bla/bla/torrents/<label>/<torrent_name>/
# avec tri specifique si label = films ou series
# a lancer ponctuellement ou periodiquement avec un cron
# ponctuellement avec netcat.sh déclenché par notify.sh coté seedbox
# principe: un batch file est ecrit puis lance par sftp
# si erreur de dl voir recup.log et contenu de .histo

# extensions dans répertoire .histo :
# hst     = torrent à récupérer
# hstok   = torrent récupéré
# hsterr  = torrent erreur de récup (erreur de dl avec lftp)
# -> répertoire /tmp/.histo  = récup en attente, quand script tourne déjà
# ex. de nom de fichier : SeedboxName_2019.11.02-13h18m29_1249CF912953450897D3149DB56DF5E1431E48D1.hst

# VARIABLES IMPORTANTES :
SECRETS="/storage/.config/flexget/secrets.yml"
BASE_STORE="/media/tera/downloads"
FILMS_DIR="/media/tera/films/"
histo='torrents/lecture' #dans quel rép distant est rangé .histo (car parfois impossible d'ecrire a la racine ftp)
histo_local="$HOME" #dans quel rép local est rangé .histo
LOCK="$histo_local"/recup.lock
RECUPLOG="$histo_local"/recup.log
b2="$histo_local"/.batch-dl   # batch de dl des fichiers torrents
EXTENSIONS="mkv,avi,mp4,m4v,iso,mpg,srt"
notif_telegram=1 # 1 pour activer, 0 pour désactiver
notif_slack=0
slack_botname="Téléchargé"
slack_boticon=":clapper:"

no_space=1 # option pr remplacer espaces par . dans noms de fichiers films et series

# Variables perso lues dans le fichier SECRETS (indentation yaml remplacée par _):
# seedbox_usr
# seedbox_pwd
# seedbox_ftp_host="ftp://serv.seedbox.com:21"
# seedbox_ftp_root="/home/me/"
# slack_hook_url="https://hooks.slack.com/services/************"

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
eval $(parse_yaml "$SECRETS")
qui=$1 # nom de la seedbox qui nous sollicite
qui_ftp_host=\$"$qui"_ftp_host ; qui_ftp_host=$(eval echo $qui_ftp_host)
qui_usr=\$"$qui"_usr ; qui_usr=$(eval echo $qui_usr)
qui_pwd=\$"$qui"_pwd ; qui_pwd=$(eval echo $qui_pwd)
now="$(date +%d.%m.%Y-%Hh%Mm%S)"
heure="$(date +%Hh%Mm%S)"
echo "-----------" $now "-----------" >> "$RECUPLOG"

# verification si le script tourne deja
if [ -f "$LOCK" ] && [ ! -z "$qui_usr" ] ; then
  # OUI : on stocke en tmp et on quitte
  mkdir -p "$histo_local"/tmp/.histo
  echo "Recup precedente pas finie, on stocke en .tmp"
  # recup des fichiers histo dans temp
  sleep 5 # attente que script precedent efface ses .hst
  lftp -u $qui_usr,$qui_pwd $qui_ftp_host <<EOF
mget -O "$histo_local/tmp/.histo" "$histo/.histo/*.hst"
mrm -f "$histo/.histo/*.hst"
exit
EOF
  echo "et on quitte..."
  exit 0
elif [ -f "$LOCK" ] && [ -z "$qui_usr" ] ; then #pas de seedbox en arg
  echo "Recup precedente pas finie, exit"
  exit 0
fi
# NON : on verrouille
touch "$LOCK"
mkdir -p "$histo_local"/.histo
if [ ! -z "$qui_usr" ] ; then
  #si on a recu un nom de seedbox en argument
  #Verif config lftp. Au lancement lftp lit /etc/lftp.conf puis ~/.lftprc puis ~/.lftp/rc
  if [ ! -f "$HOME/.lftprc" ] ; then
    echo "Pas de fichier de config perso pour lftp, on le crée ici: ~/.lftprc" >> "$RECUPLOG"
    echo '# fichier configuration lftp créé par recup.sh le' $now > "$HOME/.lftprc"
    echo 'set ftp:ssl-force true' >> "$HOME/.lftprc"  #oblige password chiffré (pas les transferts)
    echo 'set ftps:initial-prot C' >> "$HOME/.lftprc" #Data Connection Security, voir RFC4217 section 9 (Clear=pas de chiffr. ni auth.)
    echo 'set sftp:auto-confirm yes' >> "$HOME/.lftprc" #Accepte automatiq la cle publique du serveur distant (mise dans .ssh/known_hosts)
    echo 'set ssl:verify-certificate false' >> "$HOME/.lftprc"
  fi
  # et on recupere les fichiers histo
  echo "Recup des fichiers .hst"
  lftp -u $qui_usr,$qui_pwd $qui_ftp_host <<EOF
mget -O "$histo_local/.histo" "$histo/.histo/*.hst"
mrm -f "$histo/.histo/*.hst"
exit
EOF
else
  #pas de nom de seedbox, on verifie si .hst presents localement
  for file in "$histo_local"/.histo/* ; do
    if [ ! -f $file ] ; then
      # pas de fichier, on quitte
      rm "$LOCK"
      echo "Pas de seedbox a interroger, pas de .hst : exit..."
      exit 0
    fi
    hstname=${file##*/}
    qui=${hstname%_*}
    qui=${qui%_*} #en 2 étapes pour autoriser un 'qui' avec des _
  done
fi

touch "$LOCK"
nb_kodi=0
while true ; do
  nb=0
  # preparation du batch de recup des torrents
  #mise en place des identifiants
  qui_ftp_host=\$"$qui"_ftp_host ; qui_ftp_host=$(eval echo $qui_ftp_host)
  qui_usr=\$"$qui"_usr ; qui_usr=$(eval echo $qui_usr)
  qui_pwd=\$"$qui"_pwd ; qui_pwd=$(eval echo $qui_pwd)
  qui_ftp_root=\$"$qui"_ftp_root ; qui_ftp_root=$(eval echo $qui_ftp_root)
  echo 'open -u' $qui_usr','$qui_pwd $qui_ftp_host > $b2
  echo 'lcd' $BASE_STORE >> $b2
  for file in "$histo_local"/.histo/"$qui"_*.hst ; do
    # si rien a recuperer on quitte
    if [ ! -f "$file" ] ; then
      echo "Rien a recuperer, exit..."
      rm "$LOCK"
      exit 0
    fi
    nb=$((nb+1))
    rep=$(cat $file)
    rep="${rep%/}"
    NAME=${rep##*/}
    FULLDIR=${rep%/*}
    DIR=${FULLDIR##*/}
    FULLDIR=${FULLDIR#$qui_ftp_root}
    STORE="$BASE_STORE"
    if [ "$DIR" != "torrents" ] ; then
      STORE="$STORE/$DIR"
    fi
    #echapement de tous les caracteres speciaux pour le -i de mirror
    SPEC_NAME=$(echo "$NAME" | sed 's/[^[:alnum:]]/\\&/g')
    echo "mirror -x .* -x .*/ -i '$SPEC_NAME' '$FULLDIR' '$STORE'" >> $b2
    # Notify slack
    text="$NAME"
    botname="\\\"username\\\":\\\"$slack_botname\\\","
    boticon="\\\"icon_emoji\\\":\\\"$slack_boticon\\\","
    payload="payload={$boticon$botname\\\"text\\\":\\\"$text\\\"}"
    if [ $notif_slack == 1 ] ; then
        echo "!curl -s --data-urlencode \"$payload\" \"$slack_hook_url\" > /dev/null 2>> \"$RECUPLOG\"" >> $b2
    fi
    if [ $notif_telegram == 1 ] ; then
        echo "!curl -s -X POST https://api.telegram.org/bot$telegram_token/sendMessage -d chat_id=$telegram_chat_id -d text=\"$text\" > /dev/null 2>> \"$RECUPLOG\"" >> $b2
    fi
    #ne pas supprimer le hst sinon prochaine boucle ne marche pas, renommer en .hstok
    echo "!mv \"$file\" \"${file}ok\"" >> $b2
    if [ "$DIR" == "films" ] || [ "$DIR" == "series" ] ; then
      # Notifier kodi au fur et a mesure des dl
      echo "!kodi-send -a \"Notification(New,$NAME,10000)\"" >> $b2
    fi
  done
  echo 'exit' >> $b2

  heure="$(date +%Hh%Mm%S)"
  echo "$heure ---> tentative de recup de $nb torrent-s sur $qui" >> "$RECUPLOG"
  #batch pret, recup lancee ici, patience...
  sleep 3 # attente deco cmd_ftp precedent
  lftp -f $b2
  
  #verif si erreur de dl
  heure="$(date +%Hh%Mm%S)"
  for file in "$histo_local"/.histo/"$qui"-*.hst ; do
    # si aucun fichier de ce serveur, tout est ok y a pas eu erreur de dl
    if [ ! -f $file ] ; then
      echo "$heure ---> transfert depuis $qui bien fini" >> "$RECUPLOG"
    else
      rep=$(cat $file)
      fautif=${rep##*/}
      #hst_file=${file##*/} v1.2.0: à effacer
      mv "$file" "$file"err
      echo "$heure ---> $qui : transfert interrompu" >> "$RECUPLOG"
      curl -s --data-urlencode "payload={\"icon_emoji\":\":heavy_exclamation_mark:\",\"username\":\"Erreur\",\"text\":\"$fautif ($qui)\"}" "$slack_hook_url" > /dev/null 2>&1
      break # erreur seulement sur le premier .hst restant
    fi
  done

  # a ce stade tout est recupere en local, sauf si lftp a echoue qqpart
  # on fait la derniere partie de complete.sh sauf qu'on move au lieu de link (pas de seed a maintenir)
  # cad notifier Medusa et repartir dans les bons repertoires si 'films' ou 'series'
  for file in "$histo_local"/.histo/*.hstok ; do
    if [ ! -f $file ] ; then
      break
    fi
    HASH=${file##*_}
    HASH=${HASH%.*}
    rep=$(cat $file)
    #echo "rep=$rep" >> "$RECUPLOG"
    rep="${rep%/}"
    NAME=${rep##*/}
    DIR=${rep%/*}
    DIR=${DIR##*/}
    #DIR est peut-etre "torrents"
    STORE="$BASE_STORE/$DIR"
    #pour info, on log la taille du torrent
    tor_size=$(du -sch "$STORE/$NAME" | awk 'END{print $1}')
    echo "$tor_size : $NAME" >> "$RECUPLOG"
    # Postprocessing vers Medusa si serie tv et recopie si film
    if [ "$DIR" == "series" ] ; then
      nb_kodi=$((nb_kodi+1))
      # si le torrent est un dossier
      if [ -d "$STORE/$NAME" ] ; then
        STORE="$STORE/$NAME"
      fi
      # si y a des dossier dedans, il faut les passer aussi
      for fold in "$STORE"/* "$STORE" ; do
        if [ -d "$fold" ] ; then
          # envoi à medusa qui va faire un move
          NAME=${rep##*/}
          echo "curl:" "nzbName=$NAME&proc_dir=$fold&proc_type=manual"
          curl -G -s -S --data-urlencode "nzbName=$NAME" \
                        --data-urlencode "proc_dir=$fold" \
                        --data-urlencode "proc_type=manual" \
                        --data-urlencode "quiet=1" \
                        http://localhost:18081/medusa/home/postprocess/processEpisode 2>&1
          #if [ $? -eq 0 ] && [ "$fold" != "$BASE_STORE/series" ] ; then
            # si l'envoi curl a medusa a reussi, on efface le dossier
            #rm -r "$fold"
          #fi
        fi
      done
    elif [ "$DIR" == "films" ] ; then
      nb_kodi=$((nb_kodi+1))
      #déplacer uniquement film et sous titres
      for file in "$STORE/$NAME"/* ; do
        #enleve /* de fin, si le torrent est un fichier seul
        file="${file%/\*}"
        name=${file##*/}
        chemin=${file%/*}'/'
        ext=${file##*.}
        #echo "film file=$file" >> "$RECUPLOG"
        if [ "${EXTENSIONS/$ext}" != "$EXTENSIONS" ] && [ -f "$file" ] && [ "${name%.*}" != "sample" ] ; then
          # DEPLACE le fichier
          #echo "film   ok=$file" >> "$RECUPLOG"
          #goodname="${name// /.}"
          goodname=$(echo "$name" | sed 's/  */\./g')
          if [ $no_space == 1 ] && [ "$name" != "$goodname" ] ; then
            #enlever ([.-.
            goodname=${goodname//[\(\)\[\]]/}
            goodname=${goodname//.-./.}
            goodname=$(echo $goodname | tr -s '.')
            goodname=${goodname#.}
            goodname_file="${chemin}${goodname}"
            mv "$file" "${goodname_file}"
          else
            goodname_file="${chemin}${name}"
            goodname="${name}"
          fi
          mv "${goodname_file}" "${FILMS_DIR}"
        fi
      done
      #notif radarr
      python "/storage/radarr.py" "${FILMS_DIR}${goodname}" "$HASH" >> "$RECUPLOG" 2>&1
      #effacer le rep ici
      #rm -r "$STORE/$NAME"
    fi
  done

  rm -f "$histo_local"/.histo/*.hstok

  # y a t-il d'autres fichiers .hst ? recu dans tmp pendant la recup en cours ? ou un transfert interrompu ?
  # si oui, fichiers .hst sont sortis de tmp pour traitement
  for file in "$histo_local"/tmp/.histo/* ; do
    if [ -f $file ] ; then
      # sors le .hst de tmp
      hstname=${file##*/}
      mv "$file" "$histo_local/.histo/$hstname"
    else
      break # rien dans tmp
    fi
  done
  for file in "$histo_local"/.histo/*.hst ; do
    if [ ! -f $file ] ; then
      # pas de fichier hst restant, c est donc fini
      rm "$LOCK"
      if [ $nb_kodi -gt 0 ] ; then
        # Update XBMC VideoLibrarys (je groupe les dl en un seul update)
        sleep 2
        kodi-send -a "UpdateLibrary(video)"
        sleep 2
        #kodi-send -a "UpdateLibrary(music)"
      fi
      # verif espace disque restant, alerte si reste moins de ~9,5Go
      disq_restant=$(df /dev/sda1 | awk '{if(NR>1)print $4}')
      disq_restant_h=$(df -h /dev/sda1 | awk '{if(NR>1)print $4}')
      seuil_alerte=10000000
      if [ "$disq_restant" -lt "$seuil_alerte" ] ; then
        if [ $notif_slack == 1 ] ; then
            curl -s --data-urlencode "payload={\"icon_emoji\":\":heavy_exclamation_mark:\",\"username\":\"Attention\",\"text\":\"Espace disque restant faible (${disq_restant_h}o)\"}" "$slack_hook_url" > /dev/null 2>&1
        fi
        if [ $notif_telegram == 1 ] ; then
            curl -s -X POST https://api.telegram.org/bot$telegram_token/sendMessage -d chat_id=$telegram_chat_id -d text="Espace disque restant faible (${disq_restant_h}o)" > /dev/null 2>&1
        fi
      fi
      echo "Exit..."
      exit 0
    else
      # sur quel seedbox (la boucle se terminera avec le 'qui' du dernier .hst trouve)
      qui=${hstname%_*}
      qui=${qui%_*} #en 2 étapes pour autoriser un 'qui' avec des _
    fi
  done
  # on recommence pour traiter les autres hst
done
