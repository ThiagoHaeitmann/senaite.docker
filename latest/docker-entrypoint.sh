#!/bin/bash
set -e

COMMANDS="adduser debug fg foreground help kill logreopen logtail reopen_transcript run show status stop wait"
START="console start restart"

# Fixing permissions for external /data volumes
mkdir -p /data/blobstorage /data/cache /data/filestorage /data/instance /data/log /data/zeoserver
mkdir -p /home/senaite/senaitelims/src
find /data  -not -user senaite -exec chown senaite:senaite {} \+
find /home/senaite -not -user senaite -exec chown senaite:senaite {} \+


# Initializing from environment variables
gosu senaite python /docker-initialize.py

function git_fixture {
  for d in `find /home/senaite/senaitelims/src -mindepth 1 -maxdepth 1 -type d`
  do
    if [ -d "$d/.git" ]; then
      git config --global --add safe.directory $d
      echo "git config --global --add safe.directory $d"
    fi
  done
}

# Fix mr.developer: fatal: detected dubious ownership in repository at ...
# https://github.com/actions/runner-images/issues/6775
# https://github.com/senaite/senaite.docker/issues/17
git_fixture

if [ -e "custom.cfg" ]; then
  buildout -c custom.cfg
  find /data  -not -user senaite -exec chown senaite:senaite {} \+
  find /home/senaite -not -user senaite -exec chown senaite:senaite {} \+
  gosu senaite python /docker-initialize.py
fi

# ZEO Server
# ZEO Server
if [[ "$1" == "zeo"* ]]; then
  # Em host-mode, não pode ficar prendendo na 8080 do host.
  # Ajusta o conf REAL usado pelo runzeo (parts/zeo/etc/zeo.conf)
  ZEO_BIND="${ZEO_BIND:-127.0.0.1}"
  ZEO_PORT="${ZEO_PORT:-8100}"

  for CONF in \
    /home/senaite/senaitelims/parts/zeo/etc/zeo.conf \
    /home/senaite/senaitelims/parts/zeoserver/etc/zeo.conf
  do
    if [ -f "$CONF" ]; then
      # força "address <bind>:<port>" (ou só "<port>", mas no host prefiro bind explícito)
      if grep -Eq '^[[:space:]]*address[[:space:]]+' "$CONF"; then
        sed -ri "s|^[[:space:]]*address[[:space:]]+.*$|  address ${ZEO_BIND}:${ZEO_PORT}|" "$CONF"
      else
        echo "  address ${ZEO_BIND}:${ZEO_PORT}" >> "$CONF"
      fi
    fi
  done

  exec gosu senaite bin/$1 fg
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
