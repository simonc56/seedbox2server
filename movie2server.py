#!/usr/bin/env python
# -*- coding:utf-8 -*-

# movie2server.py
# Système de gestion des films copiés vers XBMC
# 29/01/2013 v1
#
#todo : afficher la progression de la copie (%age)

from datetime import datetime
import os.path
import glob
import sys
import re
import shutil

chemin_films  = "O:\\Films\\"
chemin_series = "O:\\Series\\"
display = "tout" # tout / nouveaux

def horodate():
    """Retourne la date et l'heure actuelle au format YYYY-MM-DD HH:MM"""
    return datetime.now().strftime("%Y-%m-%d %H:%M")
    
class unFilm():
    """Un film. Il contient son nom, ses lieux
    d'origine et destination, sa date de copie."""
    
    def __init__(self, nom, date="                ", chemin_desti=None):
        self.nom_complet = nom
        self.nom_propre = "0"
        self.date = date
        chemin = nom.split("\\")
        self.origine = "\\".join(chemin[:-1])
        self.titre = chemin[-1]
        self.sortie = chemin_desti
        # verifions si c'est un épisode de série tv
        self.tv = False
        season, episode = unFilm.testSerie(self.titre)
        if (season, episode) != (-1, -1):
            self.season = int(season)
            self.episode = int(episode)
            self.tv = True

    def testSerie(titre):
        """Parse le nom du fichier pour savoir
        si c'est un épisode de série tv.
        Renvoie True si c'est le cas."""
        regex = re.compile('\D(?P<sai>\d{1,2})\D(?P<epi>\d\d)')
        if regex.search(titre):
            sea_epi = regex.search(titre).groups()
            return [int(i) for i in sea_epi]
        return [-1,-1]

    def __str__(self):
        if self.date == "                ":
            line = " "*16+"|"+self.titre
        else:
            line = self.date+"|"+self.titre
        return line

    def estRepertorie(self,sauveg):
        """Vérifie si le film est déja répertorié dans
        le fichier de sauvegarde (cad a déja été copié)."""
        if self.nom in sauveg.list:
            return True
        else:
            return False

    def definirSortie(self):
        """Définir le répertoire vers lequel le film sera copié."""
        if self.tv: # épisode de série tv
            self.nom_propre = "0"
            mots_titre = re.split("\W+|_+",self.titre)[:3]
            ok = 0
            print(series)
            for serie in series: #dossiers de serie tv dispo en sortie
                mots_serie = re.split("\W+|_+",serie)
                print(mots_titre)
                for i in range(min(len(mots_serie),3)):
                    if mots_titre[i].lower() == mots_serie[i].lower(): ok+=1
                if ok >= 1:
                    self.nom_propre = serie
                    print("! trouvé ! "+serie)
                ok = 0
            if self.nom_propre == "0":
                self.nom_propre = input("Nom de la série: ")
                self.sortie = chemin_series+self.nom_propre+"\\season "+str(self.season)+"\\"
                return "serie" #indique qu'il faudra créer le répertoire de la série
            if ("season "+str(self.season)) not in os.listdir(chemin_series+self.nom_propre):
                return "season" #indique qu'il faudra créer le répertoire de la saison
            self.sortie = chemin_series+self.nom_propre+"\\season "+str(self.season)+"\\"
            return "ok"
        else: #film classique
            self.nom_propre = input("Nom du film : ")
            self.sortie = chemin_films+self.nom_propre+"\\"
            return "film" # indique qu'il faudra créer le répertoire du film


    def daterNow(self):
        """Inscrit la date actuelle à côté d'un film"""
        self.date = horodatage()

    def copier(self):
        """Copier le film vers le répertoire de sortie."""
        creer = self.definirSortie()
        if creer == "serie":
            os.mkdir(chemin_series+self.nom_propre)
            os.mkdir(chemin_series+self.nom_propre+"\\season "+str(self.season))
        if creer == "season":
            os.mkdir(chemin_series+self.nom_propre+"\\season "+str(self.season))
        if creer == "film":
            os.mkdir(chemin_films+self.nom_propre)
        ecrase = "o"
        if self.titre in os.listdir(self.sortie):
            ecrase = input("Fichier déjà existant, écraser? (O/n) ")
        if ecrase != 'n':
            print("\nDE   "+self.nom_complet)
            print("VERS "+self.sortie)
            valide = input("ok? (O/n) ")
            if valide != "n":
                deb = datetime.now()
                print(deb.strftime("%H:%M:%S")+" Copie en cours...")
                shutil.copyfile(self.nom_complet, self.sortie+self.titre)
                fin = datetime.now()
                delai = fin - deb
                input(fin.strftime("%H:%M:%S")+" Copie terminée en "+str(delai.seconds//60)+" minutes. (entrée)")
                return
        input("Ok, on ne copie pas. (entrée)")
            

#fin-class-unFilm------------------------------------------

class uneArchive():
    """Une archive listant des films avec leurs dates d'upload.
    Elle contient un dictionnaire 'nom:date' et un booléen 'writable'
    qui indique si on peut la sauvegarder dans le fichier"""
    
    def __init__(self, file_sauv):
        """Lit le fichier de sauvegarde et le met en mémoire"""
        self.list = {}
        try:
            with open(file_sauv,"r") as file:
                brut = file.read().split("\n")
                for line in brut:
                    if "|" in line:
                        date, film = line.split("|")
                        self.list[film] = date
            print("ok fichier de sauvegarde lu.")
            self.writable = True
        except IOError:
            print("Fichier de sauvegarde non trouvé!")
            try:
                with open(file_sauv,"w") as file:
                    input("On en crée un nouveau. (entrée)")
                self.writable = True
            except IOError:
                print("Et impossible de le créer ici: "+file_sauv)
                input("Il n'y aura pas de sauvegarde des actions faites. (entrée)")
                self.writable = False

    def __repr__(self):
        """Affiche le contenu de l'archive"""
        bloc = []
        for cle in self.list:
            film = unFilm(cle, self.list[cle])
            bloc.append(str(film))
        return "\n".join(bloc)

    def ajoute(self, titre):
        """Rajoute un film (avec la date actuelle) dans l'archive."""
        nom, date = titre, horodate()
        self.list[nom] = date

    def enleve(self, titre):
        """Enlève un film de l'archive."""
        del(self.list[titre])

    def nettoyer(self, films_rep, touch):
        """Enlève de la sauvegarde les films qui ne sont plus dans le répertoire donné."""
        titres_rep = [film.titre for film in films_rep]
        poubelle = []
        for titre_sauveg in self.list:
            if titre_sauveg not in titres_rep:
                print(titre_sauveg)
                poubelle.append(titre_sauveg)
        for i in poubelle:
            self.enleve(i)
            touch += 1
        if poubelle:
            print("└─> "+str(len(poubelle))+" films nettoyés de la sauvegarde.\n")

    def sauver(self, fichier):
        """Enregistre les modifications de l'archive dans le fichier de sauvegarde."""
        if self.writable:
            print("MAJ Sauvegarde")
            try:
                with open(fichier,"w") as file:
                    file.write(str(self))
            except IOError:
                print("Erreur de sauvegarde!\nLes actions ne seront pas mémorisées.")
        else:
            print("Il n'est pas possible de sauvegarder, je t'avais prévenu!")


#fin-class-uneArchive----------------------------------------

def trouverSeries(chemin):
    """Renvoie les noms des séries trouvées dans le répertoire donné."""
    try:
        return os.listdir(chemin)
    except IOError:
        input("Erreur !\nAccès impossible au dossier XBMC !")
        exit()

def getpath():
    """Renvoie le répertoire courant."""
    if '/' in sys.argv[0]:
      chemin=os.path.abspath('/'.join(sys.argv[0].split('/')[:-1]))
    else:
      chemin=os.getcwd()
    return chemin

def getfilms(chemin):
    """Renvoie la liste des fichiers vidéo
    dans le répertoire passé en argument."""
    #recuperation des noms de fichiers
    fichiers = []
    liste = glob.glob(chemin+"\\*")
    for file in liste:
        if os.path.isdir(file):
            fichiers.extend(getfilms(file))
        else:
            fichiers.append(file)
    # reg expr. des extensions de films
    filmext=re.compile('(avi|mkv|mp4|mpg|m4v)$')
    films = [fich for fich in fichiers if filmext.search(fich)]
    return films

def afficherTitre():
    print("────────────────────────┤ Movie to XBMC ├───────────────────────")

def afficherFilms(films, chemin):
    if display == "nouveaux":
        print("\nContenu de "+chemin+" :\n")
    else:
        print("\nNouveau contenu de "+chemin+" :\n")
    print("───┬──────────────────┬─────────────────────────────────────────")
    print("N° │ Date de copie    │ Fichier vidéo")
    print("───┼──────────────────┼─────────────────────────────────────────")
    titre_brut = [i.titre for i in films if display == "nouveaux" or i.date == "                "]
    date_brut = [i.date for i in films if display == "nouveaux" or i.date == "                "]
    n = 1
    for titre in titre_brut:
        print(str(n).zfill(2)+" │ "+date_brut[n-1]+" │ "+titre)
        n += 1
    print("───┴──────────────────┴─────────────────────────────────────────")
    return titre_brut
    

def afficherArchive():
    print("\nArchive :")
    print(archive)

def daterFilms(liste, archive):
    """Récupère la date de copie pour les films
    qui ont déjà été copiés précédemment (sauvegarde)."""
    for film in liste:
        if film.titre in archive:
            film.date = archive[film.titre]

def menu(titres, archive, display, films_rep_courant):
    """Affiche le menu interactif pour l'utilisateur."""
    print("\n1 - Copier vers XBMC")
    print("2 - Afficher "+display)
    print("3 - Déclarer comme déjà copié")
    print("4 - Sauver et Quitter\n")
    c = input("Choix: ")
    if c == "1":
        num = input("Lequel: ")
        nums = [int(i) for i in re.split("\W+", num)]
        for i in nums:
            if i > len(titres):
                return (4, display)
            print(titres[i-1])
            for elu in films_rep_courant:
                if elu.titre == titres[i-1]:
                    elu.copier()
                    archive.ajoute(elu.titre)
    elif c == "2":
        display = switchDisplay(display)
    elif c == "3": # déclarer comme déjà copié
        num = input("Lequel: ")
        nums = [int(i) for i in re.split("\W+", num)]
        for i in nums:
            if i > len(titres):
                return (4, display)
            print(titres[i-1])
            elu = titres[i-1]
            archive.ajoute(elu)
    elif c == "4": # sauver et quitter
        archive.nettoyer(films_rep_courant, touch)
        if touch > 0:
            archive.sauver(chemin_sauv)
            #print(archive)
    else:
        print("Taper 1, 2, 3 ou 4")
    return (c, display)

def switchDisplay(display):
    """Bascule l'affichage entre les 'nouveaux' ou 'tout' les films."""
    if display == "tout":
        return "nouveaux"
    else:
        return "tout"


#### MAIN ####
# 1. on récupère le chemin courant
chemin = getpath()
# 2. on récupère la sauvegarde
chemin_sauv = chemin+"\\movies.cfg"
archive = uneArchive(chemin_sauv)
touch = 0 #sert à verifier si l'archive change
# 3. On récupère la liste des films du répertoire courant
liste_brute = getfilms(chemin)
films_rep_courant = [unFilm(item) for item in liste_brute]
# 4. On date ceux qui sont déjà copiés
daterFilms(films_rep_courant, archive.list)
# 5. On affiche les films
os.system("cls")
afficherTitre()
affich = afficherFilms(films_rep_courant, chemin)
# 6. On récupère la liste des séries tv dispo en sortie
series = trouverSeries(chemin_series)
# 7. On affiche le menu
c = 1
while c != "4":
    c, display = menu(affich, archive, display, films_rep_courant)
    if c == "1" or c == "2" or c =="3":
        os.system("cls")
        afficherTitre()
        if c != 2:
            daterFilms(films_rep_courant, archive.list)
            touch += 1
        affich = afficherFilms(films_rep_courant, chemin)
print("\n--fin")

#--EOF

