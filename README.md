## Automatisation pour seedbox : notify.sh, netcat.sh & recup.sh

Téléchargement auto des contenus de la seedbox vers la maison.

__notify__ est sur la seedbox, __netcat__ et __recup__ sont sur le pc maison.

Aucune dépendance, fonctionne uniquement avec le shell et le binaire sshpass. Testé sur LibreElec 8.2.

### notify.sh

rtorrent exécute notify.sh à la fin de chaque téléchargement torrent (1 ligne ajoutée à rtorrent.rc)

notify crée un fichier .histo déclarant le torrent complété puis envoie une requête http à la maison, lue par netcat.sh

### netcat.sh

netcat ouvre un port sur la machine maison en attente d'une requête http

à la réception d'une requête http définie, netcat lance recup.sh

### recup.sh

lancé manuellement ou par netcat.sh, il se connecte en ftp à la seedbox, vérifie si des téléchargements sont complétés (présence de fichiers .histo) et les rapatrie en ftp

il y a un mécanisme qui protège des interruptions ou du lancement du script s'il tourne déjà. Une notification est envoyée (sur slack) à chaque torrent rappatrié.


## [obsolète] Garder un historique des copies manuelles : movie2server.py

Système basique de mémorisation des films copiés vers un serveur, copie manuel, pas terrible, je garde en souvenir :)
