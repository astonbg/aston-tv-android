#!/bin/sh
set -eu
test "$(id -u)" = 0 || { echo 'Run with sudo.'; exit 1; }
SOURCE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TARGET=/opt/aston-premium4
test -f "$TARGET/docker-compose.yml" && test -f "$TARGET/app/gateway.py"
cd "$SOURCE"
sha256sum -c SHA256SUMS
docker run --rm -v "$SOURCE:/verify:ro" -w /verify python:3.12-alpine python3 -m unittest discover -p 'test_*.py' -v
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="$TARGET/backups/mobile-$STAMP"
mkdir -p "$BACKUP" "$TARGET/session-data"
chmod 700 "$TARGET/session-data"
cp -p "$TARGET/app/gateway.py" "$BACKUP/gateway.py"
cp -p "$TARGET/docker-compose.yml" "$BACKUP/docker-compose.yml"
rollback() {
    cp -p "$BACKUP/gateway.py" "$TARGET/app/gateway.py"
    cp -p "$BACKUP/docker-compose.yml" "$TARGET/docker-compose.yml"
    (cd "$TARGET" && docker compose up -d)
    echo "Update failed. Restored original files from $BACKUP"
}
trap 'rollback' HUP INT TERM
install -m 644 "$SOURCE/gateway.py" "$TARGET/app/gateway.py"
install -m 644 "$SOURCE/docker-compose.yml" "$TARGET/docker-compose.yml"
if ! (cd "$TARGET" && docker compose up -d); then rollback; exit 1; fi
READY=0
for n in 1 2 3 4 5; do
    if docker exec aston-premium4-gateway python3 -c "import urllib.request,json; r=json.load(urllib.request.urlopen('http://127.0.0.1:8416/healthz',timeout=5)); assert r['version']=='4.1.0'"; then READY=1; break; fi
    sleep 2
done
if test "$READY" != 1; then rollback; exit 1; fi
docker exec aston-premium4-gateway python3 -c "import os,tempfile; p=os.environ['ASTON_PUBLIC_SESSION_FILE']; assert p=='/data/gateway_sessions.json'; f=tempfile.TemporaryFile(dir='/data'); f.close(); print('Persistent session directory: writable')"
trap - HUP INT TERM
echo "Gateway 4.1.0 installed. Backup: $BACKUP"
echo 'Existing memory-only pairings cannot survive this first restart. Pair once after the update.'
echo 'Future restarts preserve pairing; revoking a device in Studio still removes its access.'
