# Snowywood local server setup

## What runs where

| Service | How | Port |
|---------|-----|------|
| MariaDB (`snowywood` DB) | Docker `snowywood-mariadb` | **3307** → 3306 |
| Game server | Docker `snowywood-server` (host network) | **1337** |

Config: `config/dbconfig.txt` — `SQL_ENABLED`, database `snowywood`, user `DBmanager`.

## Quick commands

```bash
# MariaDB (already running if container exists)
docker start snowywood-mariadb

# Re-compile after code changes
/home/blob/Snowywood/tools/compile-in-container.sh

# Start / stop game server
docker start snowywood-server    # if stopped
docker stop snowywood-server
/home/blob/Snowywood/tools/run-server.sh   # foreground

# Logs
docker logs -f snowywood-server
```

## Connect as a player

Use BYOND client (Windows) and connect to:

`byond://127.0.0.1:1337`

Linux BYOND build is server-only (no graphical client).

## Native host BYOND (optional)

Requires 32-bit libs (Arch: `lib32-glibc`, `lib32-gcc-libs`, etc.) — needs sudo:

```bash
sudo pacman -S lib32-glibc lib32-gcc-libs lib32-openssl lib32-libmariadb
source /home/blob/byond-install/byond/bin/byondsetup   # after: cd byond && make here
```

## Re-import database

```bash
docker exec -i snowywood-mariadb mariadb -u DBmanager -pWhite250 snowywood \
  < /home/blob/Snowywood/SQL/tgstation_schema.sql
docker exec snowywood-mariadb mariadb -u DBmanager -pWhite250 snowywood \
  -e "INSERT INTO schema_revision (major, minor) VALUES (5, 9);"
```
