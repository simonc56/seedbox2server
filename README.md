## Automatisation pour seedbox : recup.sh, notify.sh & netcat.sh

Téléchargement auto des contenus de la seedbox vers la maison

recup et netcat sont sur le pc maison, notify est sur la seedbox

### netcat.sh

netcat ouvre un port sur la machine maison en attente d'une requête http

à la réception d'une requête http définie, netcat lance recup.sh

### notify.sh

rtorrent exécute notify.sh à la fin de chaque téléchargement torrent (1 ligne ajoutée à rtorrent.rc)

notify crée un fichier .histo déclarant le torrent complété puis envoie une requête http à la maison, lue par netcat.sh

### recup.sh

lancé manuellement ou par netcat.sh, il se connecte en ftp à la seedbox, vérifie si des téléchargements sont complétés (présence de fichiers .histo) et les rapatrie en ftp

il y a un mécanisme qui protège des interruptions ou du lancement du script s'il tourne déjà


## [obsolète] Garder un historique des copies manuelles : movie2server.py

Système de gestion des films copiés vers une base de données (Kodi, ...)

Ancien fonctionnement, manuel donc nul :)
