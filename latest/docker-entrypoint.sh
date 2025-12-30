#!/bin/bash
set -euo pipefail

COMMANDS="adduser debug fg foreground help kill logreopen logtail reopen_transcript run show status stop wait"
START="console start restart"

log() { echo "[$(date -Is)] $*"; }

# -----------------------
# FS / permissions
# -----------------------
mkdir -p /data/blobstorage /data/cache /data/filestorage /data/instance /data/log /data/zeoserver
mkdir -p /home/senaite/senaitelims/src

# Evita lock/permissão cagada (não falha o boot se algum path der ruim)
find /data -not -user senaite -exec chown senaite:senaite {} \+ 2>/dev/null || true
find /home/senaite -not -user senaite -exec chown senaite:senaite {} \+ 2>/dev/null || true

# -----------------------
# Role detection + sane defaults
# -----------------------
ROLE="custom"
ARG1="${1:-}"

if [[ "$ARG1" == zeo* ]]; then
  ROLE="zeo"
elif [[ " $START " == *" $ARG1 "* ]]; then
  ROLE="web"
elif [[ " $COMMANDS " == *" $ARG1 "* ]]; then
  ROLE="web"
fi

export SENAITE_ROLE="$ROLE"

# Defaults bons pro host-mode:
# - ZEO não pode ficar “pegando” 8080 do host (conflita com o web)
if [[ "$ROLE" == "zeo" ]]; then
  export ZEO_BIND="${ZEO_BIND:-127.0.0.1}"
  export ZEO_PORT="${ZEO_PORT:-8100}"
fi

# Web precisa saber onde tá o ZEO
if [[ "$ROLE" == "web" ]]; then
  export ZEO_ADDRESS="${ZEO_ADDRESS:-127.0.0.1:8100}"
  export WAIT_FOR_ZEO="${WAIT_FOR_ZEO:-1}"
  export WAIT_FOR_ZEO_TIMEOUT="${WAIT_FOR_ZEO_TIMEOUT:-240}"
  export WAIT_FOR_ZEO_INTERVAL="${WAIT_FOR_ZEO_INTERVAL:-2}"
fi

# HTTP_PORT já existe no seu docker-initialize.py
export HTTP_PORT="${HTTP_PORT:-8080}"

# -----------------------
# init from env vars (mantém fluxo original)
# -----------------------
gosu senaite python /docker-initialize.py

git_fixture() {
  for d in $(find /home/senaite/senaitelims/src -mindepth 1 -maxdepth 1 -type d 2>/dev/null); do
    if [ -d "$d/.git" ]; then
      git config --global --add safe.directory "$d" >/dev/null 2>&1 || true
      log "git safe.directory: $d"
    fi
  done
}
git_fixture

if [ -e "custom.cfg" ]; then
  buildout -c custom.cfg
  find /data -not -user senaite -exec chown senaite:senaite {} \+ 2>/dev/null || true
  find /home/senaite -not -user senaite -exec chown senaite:senaite {} \+ 2>/dev/null || true
  gosu senaite python /docker-initialize.py
fi

# -----------------------
# Helpers
# -----------------------
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

force_zeo_address() {
  local bind="${ZEO_BIND:-127.0.0.1}"
  local port="${ZEO_PORT:-8100}"
  local conf
  conf="$(pick_zeo_conf)"

  log "[zeo] conf=$conf"
  log "[zeo] forcing address ${bind}:${port}"
  log "[zeo] before:"
  grep -nE '^[[:space:]]*address[[:space:]]+' "$conf" || true

  if grep -Eq '^[[:space:]]*address[[:space:]]+' "$conf"; then
    sed -ri "s|^[[:space:]]*address[[:space:]]+.*$|  address ${bind}:${port}|" "$conf"
  else
    echo "  address ${bind}:${port}" >> "$conf"
  fi

  log "[zeo] after:"
  grep -nE '^[[:space:]]*address[[:space:]]+' "$conf" || true

  # fail-fast se alguém “deixou” 8080
  if grep -Eq '^[[:space:]]*address[[:space:]]+.*(:8080|[[:space:]]8080)$' "$conf"; then
    log "[zeo] ERROR: zeo.conf ainda aponta pra 8080 (host-mode vai conflitar)"
    exit 1
  fi
}

maybe_force_unlock() {
  if [ "${ZEO_FORCE_UNLOCK:-0}" != "1" ]; then
    return 0
  fi

  local lock="/data/filestorage/Data.fs.lock"
  if [ -e "$lock" ]; then
    log "[zeo] ZEO_FORCE_UNLOCK=1 -> removendo $lock"
    rm -f "$lock" || true
  fi
}

wait_for_zeo() {
  if [ "${WAIT_FOR_ZEO:-1}" != "1" ]; then
    return 0
  fi

  local addr="${ZEO_ADDRESS:-127.0.0.1:8100}"
  local host="${addr%:*}"
  local port="${addr##*:}"
  local timeout="${WAIT_FOR_ZEO_TIMEOUT:-240}"
  local interval="${WAIT_FOR_ZEO_INTERVAL:-2}"

  log "[web] esperando ZEO em ${host}:${port} timeout=${timeout}s"
  local start_ts now_ts
  start_ts="$(date +%s)"

  while true; do
    if command -v nc >/dev/null 2>&1; then
      nc -z "$host" "$port" >/dev/null 2>&1 && break
    else
      (echo >"/dev/tcp/${host}/${port}") >/dev/null 2>&1 && break || true
    fi

    now_ts="$(date +%s)"
    if [ $((now_ts - start_ts)) -ge "$timeout" ]; then
      log "[web] ERROR: ZEO não abriu ${host}:${port} em ${timeout}s"
      exit 1
    fi

    log "[web] ainda não... ${host}:${port}"
    sleep "$interval"
  done

  log "[web] ZEO OK em ${host}:${port}"
}

# -----------------------
# Routing
# -----------------------
if [[ "$ARG1" == zeo* ]]; then
  force_zeo_address
  maybe_force_unlock
  exec gosu senaite "bin/$ARG1" fg
fi

if [[ " $START " == *" $ARG1 "* ]]; then
  wait_for_zeo
  exec gosu senaite bin/instance console
fi

if [[ " $COMMANDS " == *" $ARG1 "* ]]; then
  exec gosu senaite bin/instance "$@"
fi

exec "$@"
