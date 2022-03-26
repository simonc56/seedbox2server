#!/usr/bin/env python
# coding: utf-8

# puisque Radarr ne sait pas gérer les films dans un unique répertoire, le post-processing est fait à la main
# par un script perso (recup.sh) qui rapatrie le film en bonne place sur le HTPC.

# objectif de ce script déclenché par recup.sh : créer un symlink du film dans le répertoire attendu par radarr en fin de dl
# puis faire un import manuel de ce fichier par l'API Radarr, et enfin ne plus monitorer ce film

# arguments : 1. final_filename_with_path, fichier d'origine qui sert à créer le symlink
#             2. torrent_hash, pour retrouver le film correspondant dans radarr
#             3. id radarr du film, optionnel, pour forcer manuellement
# exemple : radarr.py "/media/tera/films/Once.Upon.a.Time.2019.1080p.x264.AC3-NoTag.mkv" "332EF42968398534129D0C4E433521D0B8D38316" [id]

# 15-aout-2019 v1.0
# 27           v1.1 resoud bug symlink avec movie_file_nopath
# 15-sept-2019 v1.2 compatible python3 (py2_encode)
# 12-octo-2019 v1.3 rescan placé en dernier car put monitored=false marche pas
# 05-juin-2021 v1.4 traduction docker_path en host_path car radarr passe dans container docker
# 23-mars-2022 v1.5 manualImport remplace RescanMovie, films passent par le répertoire "mappage chemin distant" de radarr, surveillance telech activé dans radarr (interval 0)

host = "192.168.0.4"
port = "7878"
apikey = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" #apikey de radarr
docker_path = "/movies"
host_path = "/storage/radarr"

import os, sys, subprocess, json, datetime

PY2 = sys.version_info[0] == 2  # True for Python 2

def py2_encode(s, encoding='utf-8'):
    if PY2:
        s = s.encode(encoding)
    return s

def py2_decode(s, encoding='utf-8'):
    if PY2:
        s = s.decode(encoding)
    return s

root_url = "http://{}:{}/radarr/api/v3/".format(host, port)
movie_file = py2_decode(sys.argv[1])
movie_hash = sys.argv[2]
movie_id = False
if len(sys.argv) > 3:
        movie_id = int(sys.argv[3])
        print("film numero: " + str(movie_id) + " pas besoin de recup l'historique")


if PY2:
        #python2
        from urllib2 import Request, urlopen
        from urllib import urlencode
else:
        #python3
        from urllib.request import Request, urlopen
        from urllib.parse import urlencode

class PutRequest(Request):
        '''class to handling putting with urllib'''
        def get_method(self, *args, **kwargs):
                return 'PUT'

def get_history():
        url_arg = {
                'page': 1,
                'pageSize': 10,
                'apikey': apikey
        }
        req = Request(root_url+"history/?"+urlencode(url_arg))
        response = urlopen(req).read()
        return response
        
def get_movie(movie_num):
        url_arg = {
                'apikey': apikey
        }
        req = Request(root_url+"movie/"+movie_num+"?"+urlencode(url_arg))
        response = urlopen(req).read()
        return response

def rescan_movie(movie_num, movie_title):
        url_arg = {
                'apikey': apikey
        }
        command_data = {
                "name": "RescanMovie",
                "movieId": movie_num
        }
        req = Request(root_url+"command?"+urlencode(url_arg), json.dumps(command_data, encoding='utf-8'))
        req.get_method = lambda: 'POST'
        req.add_header('Content-Type', 'application/json')
        response = urlopen(req).read()
        return response
        
def put_movie(data):
        url_arg = {
                'apikey': apikey
        }
        req = Request(root_url+"movie?"+urlencode(url_arg), py2_encode(json.dumps(data, encoding='utf-8')))
        req.get_method = lambda: 'PUT'
        req.add_header('Content-Type', 'application/json')
        response = urlopen(req).read()
        return response

def get_queuedetails(movie_num):
        url_arg = {
                'apikey': apikey,
                'movieId': movie_num
        }
        req = Request(root_url+"queue/details?"+urlencode(url_arg))
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
        req = Request(root_url+"manualimport?"+urlencode(url_arg))
        response = urlopen(req).read()
        return response

def post_manualimport(file_list):
        url_arg = {
                'apikey': apikey
        }
        data = {
            "name": "ManualImport",
            "files": file_list,
            "importMode": "move"
        }
        req = Request(root_url+"command?"+urlencode(url_arg), json.dumps(data, encoding='utf-8'))
        req.get_method = lambda: 'POST'
        req.add_header('Content-Type', 'application/json;charset=utf-8')
        response = urlopen(req).read()
        return response

# si besoin je récupère l'historique des films que Radarr a envoyé à rtorrent pour retrouver l'id corresp
if not movie_id:
        print("radarr.py : transmission a radarr de " + py2_encode(movie_file))
        hist = json.loads(get_history())["records"]
        #print("historique radarr recupere, contient " + str(len(hist)) + " lignes")
        # je cherche le numéro de film correspondant à notre film
        for movie in hist:
                if movie["eventType"] == "grabbed" and movie["downloadId"] == movie_hash: # trouvé!
                        movie_id = movie["movieId"]
                        #size = movie["data"]["size"]
                        print("film correspondant (torrent hash=" + movie_hash + ") trouve dans radarr, id=" + str(movie_id))
                        break
# si j'ai un id de film correspondant dans radarr, je maj radarr
if movie_id:
        movie_file_nopath = movie_file.split("/").pop()
        movie_data = json.loads(get_movie(str(movie_id)))
        print("donnees radarr du film [" + py2_encode(movie_data["title"]) + "] bien recuperees")
        #je recupere le nom de fichier attendu par radarr (parfois différent si j'ai renommé) et le répertoire attendu
        movie_queue = json.loads(get_queuedetails(str(movie_id)))
        expected_filename = movie_queue[0].get('title')
        movie_path = movie_queue[0].get('outputPath').replace(docker_path, host_path).replace(expected_filename, "")
        if not os.path.exists(movie_path):
                os.mkdir(movie_path)
        if not os.path.islink(movie_path + expected_filename):
                os.symlink(movie_file, movie_path + expected_filename)
                print("lien symbolique cree : " + py2_encode(movie_path) + py2_encode(expected_filename))
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
                else:
                    print("fichier attendu:" + py2_encode(expected_filename) + " fichier trouve:" + py2_encode(fich["relativePath"]))
            cmd_resp = json.loads(post_manualimport(fichiers))
            #puis radarr scanne le rep pour trouver le fichier (deprecated le 23 mars 2022)
            #cmd_resp = json.loads(rescan_movie(movie_id, movie_data['title']))
            print("monitored=False envoye, commande de manualImport du film envoyée a radarr, command id=" + str(cmd_resp['id']))
        else:
            print("pas de fichier correspondant trouve dans " + py2_encode(movie_path))
            print("fichier attendu: " + py2_encode(expected_filename))
else:
        print("film introuvable dans radarr avec le hash torrent")
        