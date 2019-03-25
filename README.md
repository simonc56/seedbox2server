## Synchro automatique seedbox/maison avec lftp

Téléchargement ftp des contenus de seedbox vers la maison.

Principe : 3 scripts shell communiquent entre eux pour déclencher la synchro à chaque fois qu'un torrent se termine.

__notify__ est sur la/les seedbox, __netcat__ et __recup__ sont sur le pc/serveur à la maison.

Fonctionne avec lftp. Testé sur LibreElec 8.2 et 9.

### notify.sh

rtorrent exécute notify.sh à la fin de chaque téléchargement torrent (1 ligne ajoutée à rtorrent.rc)

notify crée un fichier .histo déclarant le torrent complété puis envoie une requête http à la maison, lue par netcat.sh

### netcat.sh

netcat ouvre un port sur la machine maison en attente d'une requête http

à la réception d'une requête http définie, netcat lance recup.sh

### recup.sh

lancé par netcat.sh (ou à la main ou par cron si vous voulez), il se connecte en ftp à la seedbox concernée, vérifie si des téléchargements sont complétés (présence de fichiers .histo) et les rapatrie en ftp.

Une notification est envoyée (sur slack) à chaque torrent rapatrié. Pas de connexion inutile au serveur toutes les x heures pour "vérifier", la connexion ftp est déclenchée uniquement si un téléchargement se termine sur la seedbox.
Capable d'utiliser les protocoles ftp, ftps, sftp et de gérer plusieurs seedbox.
