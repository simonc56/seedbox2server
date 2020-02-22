## Sync rtorrent seedbox and home with ftp

Automatic ftp downloading of seedbox content to home server without additional software installed on seedbox (because sometimes we can't).

How it works: 3 shell scripts communicate to each other to fetch files each time a torrent is downloaded.
__notify.sh__ is on seedbox, __listener.sh__ and __fetcher.sh__ are on server/nas at home.
 __lftp__ is required on home server.

### notify.sh

rtorrent executes notify.sh each time a torrent download completes (1 line added to rtorrent.rc). notify.sh creates a small .histo file declaring the completed torrent then sends a http request to home server, read by listener.sh

### listener.sh

It opens a port on home server and waits for http request from notify.sh

Upon http request reception, listener.sh runs fetcher.sh

This script can be replaced by a cron job running fetcher.sh every x minutes if you prefer.

### fetcher.sh

Launched by listener.sh (or manually or with cron job if you wish), it connects to seedbox through ftp, checks if there are completed torrents and fetch them.

A notification is sent (slack or telegram) for each torrent fetched and to library softwares like Medusa or Radarr for import. No need to "poll" seedbox every x minutes for new files, ftp connexion is triggered only if a torrent is completed on seedbox.

It works with protocols ftp, ftps, sftp and can handle many seedboxes.
If there is network problem or if server is down, it will fetch torrents later.

## Setup

1. Edit config.yml and the first lines of notify.sh and fetcher.sh
2. Make sure you have lftp on home server
3. Choose a connexion port for listener.sh and check that it can be reached by notify.sh (maybe port forwarding needed)
3. Copy notify.sh to seedbox and add this edited line in .rtorrent.rc configfile:
  `method.set_key = event.download.finished,notif,"execute2={/home/***/notify.sh,$d.hash=,$d.base_path=}"`
4. Restart rtorrent
5. Run listener.sh (or if you prefer you can run fetcher.sh periodically with a cron job)
