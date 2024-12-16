#!/usr/bin/env python
# coding: utf-8

# puisque Radarr ne sait pas gérer les films dans un unique répertoire, le post-processing est fait à la main
# par un script perso (recup.sh) qui rapatrie le film en bonne place sur le HTPC.

# objectif de ce script déclenché par recup.sh : créer un symlink/hardlink du film dans le répertoire attendu par radarr en fin de dl
# puis faire un import manuel de ce fichier par l'API Radarr, et enfin ne plus monitorer ce film

# arguments : 1. final_filename_with_path, fichier d'origine qui sert à créer le symlink
#             2. torrent_hash, pour retrouver le film correspondant dans radarr
#             3. id radarr du film, optionnel, pour forcer manuellement
# exemple : radarr.py "/media/tera/films/Once.Upon.a.Time.2019.1080p.x264.AC3-NoTag.mkv" "332EF42968398534129D0C4E433521D0B8D38316"

# 15-aout-2019 v1.0
# 27           v1.1 resoud bug symlink avec movie_file_nopath
# 15-sept-2019 v1.2 compatible python3 (py2_encode)
# 12-octo-2019 v1.3 rescan placé en dernier car put monitored=false marche pas
# 05-juin-2021 v1.4 traduction docker_path en host_path car radarr passe dans container docker
# 23-mars-2022 v1.5 manualImport remplace RescanMovie, films passent par le répertoire "mappage chemin distant" de radarr, surveillance telech activé dans radarr avec interval maxi (120)
# 31-juil-2022 v1.6 gestion des messages d'erreur dans queue et manualImport
# 11-juin-2023 v1.7 compatible python 3 uniquement
# 09-déce-2024 v1.8 chown root + symlink pour docker et non pas host (radarr 5.15.1.9463 follow symlink)

host = "192.168.0.4"
port = "7878"
apikey = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" #apikey de radarr
docker_path = "/movies"
host_path = "/storage/radarr"
hardlink = False # pas testé avec True, chemin fullpath ne marche pas avec radarr dans docker car volume relatif

import os, sys, json
from time import sleep

root_url = "http://{}:{}/radarr/api/v3/".format(host, port)
movie_file = sys.argv[1]
movie_hash = sys.argv[2]
movie_id = False

from urllib.request import Request, urlopen
from urllib.parse import urlencode

class PutRequest(Request):
    '''class to handling putting with urllib'''
    def get_method(self, *args, **kwargs):
        return 'PUT'
        
def get_movie(movie_num):
    url_arg = {
        'apikey': apikey
    }
    req = Request(root_url + "movie/" + movie_num + "?" + urlencode(url_arg))
    response = urlopen(req).read()
    return response
 
def post_refreshmonitored(sec=5):
    url_arg = {
        'apikey': apikey
    }
    data = { 
        "name": "RefreshMonitoredDownloads"
    }
    headers = {
        'Content-Type': 'application/json;charset=utf-8'
    }
    req = Request(root_url + "command?" + urlencode(url_arg), headers=headers, data=json.dumps(data).encode("utf-8"))
    req.get_method = lambda: 'POST'
    response = urlopen(req).read()
    sleep(sec)
    return response
    
def put_movie(data):
    url_arg = {
        'apikey': apikey
    }
    headers = {
        'Content-Type': 'application/json'
    }
    req = Request(root_url + "movie?" + urlencode(url_arg), headers=headers, data=json.dumps(data).encode("utf-8"))
    req.get_method = lambda: 'PUT'
    req.add_header('Content-Type', 'application/json')
    response = urlopen(req).read()
    return response

def get_queuedetails():
    url_arg = {
        'apikey': apikey
    }
    req = Request(root_url + "queue/details?" + urlencode(url_arg))
    response = urlopen(req).read()
    return response

def get_manualimport(movie_num, movie_folder="", download_id=""):
    url_arg = {
        'apikey': apikey,
        'downloadId': download_id,
        'movieId': movie_num,
        'folder': movie_folder,
        'filterExistingFiles': False
    }
    req = Request(root_url + "manualimport?" + urlencode(url_arg))
    response = urlopen(req).read()
    return response

def post_manualimport(file_list, mode="move"):
    url_arg = {
        'apikey': apikey
    }
    data = {
        "name": "ManualImport",
        "files": file_list,
        "importMode": mode  # move ou copy
    }
    headers = {
        'Content-Type': 'application/json;charset=utf-8'
    }
    req = Request(root_url + "command?" + urlencode(url_arg), headers=headers, data=json.dumps(data).encode("utf-8"))
    req.get_method = lambda: 'POST'
    response = urlopen(req).read()
    return response

# refresh pour passer à l'état "importPending" les "grabbed" de la file d'attente qui sont finis de télécharger
# utile si je mets l'interval de refresh de radarr au max (120min)
post_refreshmonitored()
# je récupère la liste des films que Radarr a envoyé à rtorrent pour retrouver l'id corresp
print("radarr.py : transmission à radarr de " + movie_file)
try:
    os.chown(movie_file, 0, 0) # rtorrent a créé le fichier en user nobody:nogroup, je remets root:root
except:
    print("Impossible de changer le proprietaire du fichier")
queue = json.loads(get_queuedetails())
# je cherche le numéro de film correspondant à notre film
for movie in queue:
    if movie["status"] == "completed" and movie["downloadId"] == movie_hash: # "trackedDownloadState"="importPending" trouvé!
        movie_id = movie.get("movieId")
        if movie.get("statusMessages"):
            for msg in movie.get("statusMessages"):
                print("Status Message: " + msg["messages"][0])
        #size = movie["data"]["size"]
        #je recupere le nom de fichier attendu par radarr (parfois différent si j'ai renommé) et le répertoire attendu
        #outputPath est le chemin attendu par radarr donc après application du mappage de chemin distant (paramètres radarr > client téléch.)
        #Mappage radarr :  Dossier distant:/home1/usr00505/torrents/films/    Chemin local:/media/downloads/import/
        #                  Dossier distant:/var/media/tera/downloads/films/  Chemin local:/media/downloads/import/
        #Dossier racine de films dans radarr : /media/movies (soit /media/tera/movies)
        full_movie_path = movie.get('outputPath').replace(docker_path, host_path)  # /storage/radarr/import/Mon.Film.mkv
        movie_file_from_docker = movie_file.replace(host_path, docker_path)  # /media/downloads/films/Mon.Film.mkv
        expected_filename = os.path.basename(full_movie_path)  # Mon.Film.mkv
        movie_path = os.path.dirname(full_movie_path)   # /media/tera/downloads/import
        extension = os.path.splitext(movie_file)[1]
        # cas particulier: si on a un répertoire en outputPath (cas des torrents avec plusieurs fichiers)
        if os.path.splitext(expected_filename)[1] != extension:
            movie_path = full_movie_path
            expected_filename = os.path.basename(movie_file)
            full_movie_path = os.path.join(movie_path, expected_filename)
        print(movie.get("title") + " trouvé dans file d'attente radarr hash=" + str(movie_hash) + " id=" + str(movie_id))
        break
# si j'ai un id de film correspondant dans radarr, je maj radarr
if movie_id:
    movie_data = json.loads(get_movie(str(movie_id)))
    print("donnees radarr du film [" + movie_data["title"] + "] bien recuperees")
    if not os.path.exists(movie_path):
        os.mkdir(movie_path)
    if not hardlink and not os.path.islink(full_movie_path):
        # os.symlink(srcFile, newFile)
        os.symlink(movie_file_from_docker, full_movie_path) # le symlink ne fonctionne que pour radarr dans docker
        print("lien symbolique créé : " + full_movie_path)
    if hardlink and not os.path.isfile(full_movie_path):
        os.link(movie_file, full_movie_path)
        print("lien physique créé : " + full_movie_path)
    #je le passe en non-monitored (on ne cherche plus à le telecharger)
    movie_data["monitored"] = False
    #et je renvoie les données à Radarr
    resp = put_movie(movie_data)
    #manualimport avec le downloadId pour purger l'historique de fichiers grabbed par radarr
    fichiers = json.loads(get_manualimport(movie_num=movie_id, download_id=movie_hash))
    if fichiers:
        for fich in fichiers:
            if fich["relativePath"] == expected_filename:
                fich["movieId"] = fich["movie"]["id"]
                fich["downloadId"] = movie_hash
                for lng in fich["languages"]:
                    print("Language: " + str(lng["id"]) + " " + lng["name"])
                print("Qualité: " + str(fich["quality"]["quality"]["id"]) + " " + fich["quality"]["quality"]["name"])
                if fich.get("rejections"):
                    print("Import impossible: " + fich["rejections"][0]["reason"])
            else:
                print("fichier trouvé " + fich["relativePath"] + " mais ne correspond pas")
        cmd_resp = json.loads(post_manualimport(fichiers))
        #puis radarr scanne le rep pour trouver le fichier (deprecated le 23 mars 2022)
        #cmd_resp = json.loads(rescan_movie(movie_id, movie_data['title']))
        print("monitored=False envoye, commande de manualImport du film envoyée a radarr, command id=" + str(cmd_resp['id']))
    else:
        print("fichier " + expected_filename + " introuvable dans " + movie_path)
else:
        print("film introuvable dans radarr avec le hash torrent")
        