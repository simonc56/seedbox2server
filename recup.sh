#!/bin/sh
#
# recuperation de fichiers sur serveur ftp, il faut sshpass et sftp
# les fichiers distants doivent se telecharger dans une arborescence
# /home/bla/bla/torrents/<label>/<torrent_name>/
# avec tri specifique si label = films ou series
# a lancer ponctuellement ou periodiquement avec un cron
# ponctuellement avec netcat.sh déclenché par notify.sh coté seedbox
# principe: un batch file est ecrit puis lance par sftp
# si erreur de dl voir recup.log et contenu de .histo

# VARIABLES IMPORTANTES :
serveur='***@server.com'
racine_ftp='/home/***/'
export SSHPASS='******'
BASE_STORE="/**/downloads"
FILMS_DIR="/**/films/"
histo='watch'
histo_local='/storage'
LOCK="$histo_local"/recup.lock
b="$histo_local"/.batch-hst   # batch de recup des .hst
b2="$histo_local"/.batch-dl   # batch de dl des fichiers torrents
b3="$histo_local"/.batch-tmp  # batch de recup des hst en tmp
EXTENSIONS="mkv,avi,mp4,m4v,iso,mpg,srt"
WEBHOOK_URL="https://hooks.slack.com/services/************"
botname="Téléchargé"
boticon=":clapper:"
botname="\\\"username\\\":\\\"$botname\\\","
boticon="\\\"icon_emoji\\\":\\\"$boticon\\\","
cmd_ftp="/storage/sshpass -e sftp -oBatchMode=no -b"
no_space=1 # option pr remplacer espaces par . dans noms de fichiers films et series

# extensions dans répertoire .histo :
# hst     = torrent à récupérer
# hstok   = torrent récupéré
# hsterr  = torrent erreur de récup (erreur de dl avec sftp)
# -> répertoire /tmp/.histo  = récup en attente, quand script tourne déjà

RECUPLOG="$histo_local"/recup.log
now="$(date +%d.%m.%Y-%Hh%Mm%S)"
heure="$(date +%Hh%Mm%S)"
echo "-----------" $now "-----------" >> "$RECUPLOG"

# verification si le script tourne deja
if [ -f "$LOCK" ] ; then
  # OUI : on stocke en tmp et on quitte
  mkdir "$histo_local/tmp"
  echo "Recup precedente pas finie, on stocke en .tmp"
  echo 'lcd' $histo_local > $b3
  # recup des fichiers histo dans temp
  echo '-get -r' "$histo/.histo" "$histo_local"/tmp >> $b3
  echo '-rm' $histo'/.histo/*' >> $b3
  echo 'bye' >> $b3
  sleep 5 # attente que script precedent efface ses .hst
  $cmd_ftp $b3 $serveur
  echo "et on quitte..."
  exit 0
else
  # NON : on verrouille
  touch "$LOCK"
  # et on recupere les fichiers histo
  echo "Recup des fichiers .hst"
  echo 'lcd' $histo_local > $b
  echo '-get -r' $histo'/.histo' $histo_local >> $b
  echo '-rm' $histo'/.histo/*' >> $b
  echo 'bye' >> $b
  $cmd_ftp $b $serveur
fi

nb_kodi=0
while true ; do
  nb=0
  # preparation du batch de recup des torrents
  echo 'lcd' $BASE_STORE > $b2
  for file in "$histo_local"/.histo/*.hst ; do
    # si rien a recuperer on quitte
    if [ ! -f "$file" ] ; then
      echo "Rien a recuperer, exit..."
      rm "$LOCK"
      exit 0
    fi
    nb=$((nb+1))
    rep=`cat $file`
    rep="${rep%/}"
    NAME=${rep##*/}
    DIR=${rep%/*}
    DIR=${DIR##*/}
    STORE="$BASE_STORE"
    if [ "$DIR" != "torrents" ] ; then
      STORE="$STORE/$DIR"
    fi
    rep=${rep#$racine_ftp}
    echo "get -r" "\"$rep\"" "\"$STORE\"" >> $b2
    # Notify slack
    text="$NAME"
    payload="payload={$boticon$botname\\\"text\\\":\\\"$text\\\"}"
    echo "!curl -s --data-urlencode \"$payload\" \"$WEBHOOK_URL\" > /dev/null 2>> \"$RECUPLOG\"" >> $b2
    #ne pas supprimer le hst sinon prochaine boucle ne marche pas, renommer en .hstok
    echo "!mv \"$file\" \"${file}ok\"" >> $b2
    if [ "$DIR" == "films" ] || [ "$DIR" == "series" ] ; then
      # Notifier kodi au fur et a mesure des dl
      echo "!kodi-send -a \"Notification(New,$NAME,10000)\"" >> $b2
    fi
  done
  echo 'bye' >> $b2

  heure="$(date +%Hh%Mm%S)"
  echo "$heure ---> tentative de recup de $nb torrent-s" >> "$RECUPLOG"
  #batch pret, recup lancee ici, patience...
  sleep 3 # attente deco cmd_ftp precedent
  $cmd_ftp $b2 $serveur
  
  #verif si erreur de dl
  echec_dl=0
  heure="$(date +%Hh%Mm%S)"
  for file in "$histo_local"/.histo/*.hst ; do
    # si aucun file tout est ok y a pas eu erreur de dl
    if [ ! -f $file ] ; then
      echo "$heure ---> transfert bien fini" >> "$RECUPLOG"
    else
      echec_dl=1
      rep=`cat $file`
      fautif=${rep##*/}
      hst_file=${file##*/}
      mv "$file" "$file"err
      echo "$heure ---> transfert interrompu" >> "$RECUPLOG"
      curl -s --data-urlencode "payload={\"icon_emoji\":\":heavy_exclamation_mark:\",\"username\":\"Erreur\",\"text\":\"$fautif\"}" "$WEBHOOK_URL" > /dev/null 2>&1
      break # erreur seulement sur le premier .hst restant
    fi
  done

  # a ce stade tout est recupere en local, sauf si sftp a echoue qqpart
  # on fait la derniere partie de complete.sh sauf qu ON BOUCLE sur les N torrents et on move au lieu de link (pas de seed a maintenir)
  # cad repartition dans les bons repertoires si 'films' ou 'series'
  for file in "$histo_local"/.histo/*.hstok ; do
    rep=`cat $file`
    echo "rep=$rep" >> "$RECUPLOG"
    rep="${rep%/}"
    NAME=${rep##*/}
    DIR=${rep%/*}
    DIR=${DIR##*/}
    #DIR est peut-etre "torrents"
    STORE="$BASE_STORE/$DIR"
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
                        http://localhost:18081/home/postprocess/processEpisode 2>&1
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
        chemin="${file/$name}"
        ext=${file##*.}
        echo "film file=$file" >> "$RECUPLOG"
        if [ "${EXTENSIONS/$ext}" != "$EXTENSIONS" ] && [ -f "$file" ] && [ "${name%.*}" != "sample" ] ; then
          # DEPLACE le fichier
          echo "film   ok=$file" >> "$RECUPLOG"
          #goodname="${name// /.}"
          goodname=$(echo "$name" | sed 's/  */\./g')
          if [ $no_space == 1 ] && [ "$name" != "$goodname" ] ; then
            goodname_file="${chemin}${goodname}" 
            mv "$file" "${goodname_file}"
          else
            goodname_file="$file"
          fi
          mv "${goodname_file}" "${FILMS_DIR}"
        fi
      done
      #effacer le rep ici
      #rm -r "$STORE/$NAME"
    fi
  done

  rm "$histo_local"/.histo/*.hstok

  # y a t-il eu des fichiers .hst recu dans tmp pendant la recup en cours ? ou un transfert interrompu ?
  # si oui, fichiers .hst sont sortis de tmp pour traitement
  for file in "$histo_local"/tmp/.histo/* ; do
    if [ ! -f $file ] && [ $echec_dl -eq 0 ] ; then
      # pas de fichier dans tmp, pas d'echec de dl, c est donc fini
      rm "$LOCK"
      if [ $nb_kodi -gt 0 ] ; then
        # Update XBMC VideoLibrarys (je groupe les dl en un seul update)
        sleep 2
        kodi-send -a "UpdateLibrary(video)"
        sleep 2
        #kodi-send -a "UpdateLibrary(music)"
      fi
      echo "Exit..."
      exit 0
    fi
    # sors le .hst de tmp
    hstname=${file##*/}
    mv "$file" "$histo_local/.histo/$hstname"
    # si echec_dl on recommence pour traiter les probables fichiers qui devaient suivre
  done
done
