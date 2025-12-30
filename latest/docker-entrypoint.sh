#!/bin/bash
set -euo pipefail

COMMANDS="adduser debug fg foreground help kill logreopen logtail reopen_transcript run show status stop wait"
START="console start restart"

log() { echo "[$(date -Is)] $*"; }

mkdir -p /data/blobstorage /data/cache /data/filestorage /data/instance /data/log /data/zeoserver
mkdir -p /home/senaite/senaitelims/src

find /data -not -user senaite -exec chown senaite:senaite {} \+ || true
find /home/senaite -not -user senaite -exec chown senaite:senaite {} \+ || true

gosu senaite python /docker-initialize.py

git_fixture() {
  for d in $(find /home/senaite/senaitelims/src -mindepth 1 -maxdepth 1 -type d 2>/dev/null); do
    if [ -d "$d/.git" ]; then
      git config --global --add safe.directory "$d" || true
      log "git safe.directory: $d"
    fi
  done
}
git_fixture

if [ -e "custom.cfg" ]; then
  buildout -c custom.cfg
  find /data -not -user senaite -exec chown senaite:senaite {} \+ || true
  find /home/senaite -not -user senaite -exec chown senaite:senaite {} \+ || true
  gosu senaite python /docker-initialize.py
fi

pick_zeo_conf() {
  if [ -f "/home/senaite/senaitelims/parts/zeo/etc/zeo.conf" ]; then
    echo "/home/senaite/senaitelims/parts/zeo/etc/zeo.conf"
    return 0
  fi
  if [ -f "/home/senaite/senaitelims/parts/zeoserver/etc/zeo.conf" ]; then
    echo "/home/senaite/senaitelims/parts/zeoserver/etc/zeo.conf"
    return 0
  fi
  return 1
}

patch_zeo_address() {
  local bind="${ZEO_BIND:-127.0.0.1}"
  local port="${ZEO_PORT:-8100}"
  local conf
  conf="$(pick_zeo_conf)"

  log "[zeo] conf=$conf"
  log "[zeo] patch -> address ${bind}:${port}"

  # mostra antes
  log "[zeo] before:"
  grep -nE '^[[:space:]]*address[[:space:]]+' "$conf" || true

  # substitui QUALQUER address existente
  if grep -Eq '^[[:space:]]*address[[:space:]]+' "$conf"; then
    sed -ri "s|^[[:space:]]*address[[:space:]]+.*$|  address ${bind}:${port}|" "$conf"
  else
    echo "  address ${bind}:${port}" >> "$conf"
  fi

  # mostra depois
  log "[zeo] after:"
  grep -nE '^[[:space:]]*address[[:space:]]+' "$conf" || true

  # trava se restou 8080
  if grep -Eq '^[[:space:]]*address[[:space:]]+.*(:8080|[[:space:]]8080)$' "$conf"; then
    log "[zeo] ERROR: zeo.conf ainda aponta pra 8080. abortando."
    exit 1
  fi
}

maybe_unlock_filestorage() {
  if [ "${ZEO_FORCE_UNLOCK:-0}" != "1" ]; then
    return 0
  fi
  local lock="/data/filestorage/Data.fs.lock"
  if [ -e "$lock" ]; then
    log "[zeo] FORCE_UNLOCK=1 -> removendo $lock"
    rm -f "$lock" || true
  fi
}

wait_for_zeo() {
  local enable="${WAIT_FOR_ZEO:-1}"
  [ "$enable" = "1" ] || return 0

  local addr="${ZEO_ADDRESS:-127.0.0.1:8100}"
  local host="${addr%:*}"
  local port="${addr##*:}"
  local timeout="${WAIT_FOR_ZEO_TIMEOUT:-240}"
  local interval="${WAIT_FOR_ZEO_INTERVAL:-2}"

  log "[web] esperando ZEO em ${host}:${port} (timeout=${timeout}s)"
  local start_ts; start_ts="$(date +%s)"

  while true; do
    nc -z "$host" "$port" >/dev/null 2>&1 && break || true

    local now_ts; now_ts="$(date +%s)"
    if [ $((now_ts - start_ts)) -ge "$timeout" ]; then
      log "[web] ERROR: ZEO não abriu ${host}:${port} em ${timeout}s"
      exit 1
    fi

    log "[web] ainda não... (${host}:${port})"
    sleep "$interval"
  done

  log "[web] ZEO OK em ${host}:${port}"
}

# ---- routing ----

if [[ "${1:-}" == zeo* ]]; then
  patch_zeo_address
  maybe_unlock_filestorage
  exec gosu senaite "bin/$1" fg
fi

if [[ " $START " == *" ${1:-} "* ]]; then
  wait_for_zeo
  exec gosu senaite bin/instance console
fi

if [[ " $COMMANDS " == *" ${1:-} "* ]]; then
  exec gosu senaite bin/instance "$@"
fi

exec "$@"
