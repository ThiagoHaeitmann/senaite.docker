#!/bin/bash
set -e

COMMANDS="adduser debug fg foreground help kill logreopen logtail reopen_transcript run show status stop wait"
START="console start restart"

# Fixing permissions for external /data volumes
mkdir -p /data/blobstorage /data/cache /data/filestorage /data/instance /data/log /data/zeoserver
mkdir -p /home/senaite/senaitelims/src

# IMPORTANT: keep ownership consistent for host volumes
find /data -not -user senaite -exec chown senaite:senaite {} \+
find /home/senaite -not -user senaite -exec chown senaite:senaite {} \+

# Initialize from environment variables (this is where ports/config are applied)
gosu senaite python /docker-initialize.py

git_fixture() {
  for d in $(find /home/senaite/senaitelims/src -mindepth 1 -maxdepth 1 -type d); do
    if [ -d "$d/.git" ]; then
      git config --global --add safe.directory "$d"
      echo "git config --global --add safe.directory $d"
    fi
  done
}

# Fix mr.developer dubious ownership
git_fixture

if [ -e "custom.cfg" ]; then
  buildout -c custom.cfg
  find /data -not -user senaite -exec chown senaite:senaite {} \+
  find /home/senaite -not -user senaite -exec chown senaite:senaite {} \+
  gosu senaite python /docker-initialize.py
fi

# Helper: patch ZEO conf (safety net)
patch_zeo_conf() {
  ZEO_BIND="${ZEO_BIND:-127.0.0.1}"
  ZEO_PORT="${ZEO_PORT:-8100}"

  for CONF in \
    /home/senaite/senaitelims/parts/zeo/etc/zeo.conf \
    /home/senaite/senaitelims/parts/zeoserver/etc/zeo.conf
  do
    [ -f "$CONF" ] || continue

    echo "[zeo] using conf: $CONF"
    echo "[zeo] requested bind: ${ZEO_BIND}:${ZEO_PORT}"
    echo "[zeo] before:"
    grep -nE '^[[:space:]]*address[[:space:]]+' "$CONF" || true

    # Replace any of:
    #   address 8080
    #   address 127.0.0.1:8080
    #   address 0.0.0.0:8080
    #   address [::]:8080
    # -> address ZEO_BIND:ZEO_PORT
    if grep -Eq '^[[:space:]]*address[[:space:]]+' "$CONF"; then
      sed -ri "s|^[[:space:]]*address[[:space:]]+.*$|  address ${ZEO_BIND}:${ZEO_PORT}|" "$CONF"
    else
      echo "  address ${ZEO_BIND}:${ZEO_PORT}" >> "$CONF"
    fi

    echo "[zeo] after:"
    grep -nE '^[[:space:]]*address[[:space:]]+' "$CONF" || true

    # Hard fail if still 8080 (prevents silent footgun in host-mode)
    if grep -Eq '^[[:space:]]*address[[:space:]]+.*:8080$|^[[:space:]]*address[[:space:]]+8080$' "$CONF"; then
      echo "[zeo] ERROR: still points to 8080 -> refusing to start"
      exit 1
    fi
  done
}

# ZEO Server
if [[ "$1" == "zeo"* ]]; then
  patch_zeo_conf

  # Optional: handle stale lock (ONLY if you explicitly allow)
  # Because removing locks blindly can be dangerous on a real multi-process setup.
  # Use: ZEO_FORCE_UNLOCK=1
  if [ "${ZEO_FORCE_UNLOCK:-0}" = "1" ]; then
    LOCK="/data/filestorage/Data.fs.lock"
    if [ -e "$LOCK" ]; then
      echo "[zeo] ZEO_FORCE_UNLOCK=1 -> removing stale lock: $LOCK"
      rm -f "$LOCK" || true
    fi
  fi

  exec gosu senaite bin/"$1" fg
fi

# Instance start
if [[ $START == *"$1"* ]]; then
  exec gosu senaite bin/instance console
fi

# Instance helpers
if [[ $COMMANDS == *"$1"* ]]; then
  exec gosu senaite bin/instance "$@"
fi

# Custom
exec "$@"
