#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-${MODE:-instance}}"

: "${HTTP_ADDRESS:=0.0.0.0}"
: "${HTTP_PORT:=8080}"
: "${ZEO_LISTEN:=127.0.0.1}"
: "${ZEO_PORT:=8100}"
: "${ZEO_ADDRESS:=127.0.0.1:${ZEO_PORT}}"
: "${ADMIN_USER:=admin}"
: "${ADMIN_PASS:=admin}"

: "${DATA_ZEO:=/data/zeo}"
: "${DATA_BLOB:=/data/blob}"
: "${DATA_VAR:=/data/var}"
: "${FIX_PERMS:=0}"
: "${PUID:=0}"
: "${PGID:=0}"

APP_DIR="/app"

log(){ echo "[senaite] $*"; }
die(){ echo "[senaite][FATAL] $*" >&2; exit 1; }

is_true() {
  case "${1,,}" in 1|true|yes|y|on) return 0 ;; *) return 1 ;; esac
}

# dirs
mkdir -p "${DATA_ZEO}" "${DATA_BLOB}" "${DATA_VAR}"

if is_true "${FIX_PERMS}"; then
  log "Fixing permissions (PUID=${PUID}, PGID=${PGID})..."
  chown -R "${PUID}:${PGID}" "${DATA_ZEO}" "${DATA_BLOB}" "${DATA_VAR}" || true
  chmod -R u+rwX,g+rwX "${DATA_ZEO}" "${DATA_BLOB}" "${DATA_VAR}" || true
fi

# ---- sanity: buildout já tem que existir
[[ -x "${APP_DIR}/bin/instance" ]]  || die "missing ${APP_DIR}/bin/instance (buildout não rodou no build?)"
[[ -x "${APP_DIR}/bin/zeoserver" ]] || die "missing ${APP_DIR}/bin/zeoserver (buildout não rodou no build?)"

# caminhos típicos gerados
ZEO_CONF="${APP_DIR}/parts/zeoserver/etc/zeo.conf"
ZOPe_CONF="${APP_DIR}/parts/instance/etc/zope.conf"

# patch ZEO conf
patch_zeo() {
  [[ -f "${ZEO_CONF}" ]] || die "missing ${ZEO_CONF}"
  # troca address
  # normalmente tem linha: address 127.0.0.1:8100
  sed -ri "s|^(\s*address\s+).*$|\1${ZEO_LISTEN}:${ZEO_PORT}|g" "${ZEO_CONF}"
  log "patched zeo.conf -> address ${ZEO_LISTEN}:${ZEO_PORT}"
}

# patch instance conf
patch_instance() {
  [[ -f "${ZOPe_CONF}" ]] || die "missing ${ZOPe_CONF}"
  # http-address
  sed -ri "s|^(\s*http-address\s+).*$|\1${HTTP_ADDRESS}:${HTTP_PORT}|g" "${ZOPe_CONF}"
  # zeo-address (normalmente aparece como: address 127.0.0.1:8100 dentro do zeoclient)
  sed -ri "s|^(\s*address\s+)[0-9\.]+:[0-9]+$|\1${ZEO_ADDRESS}|g" "${ZOPe_CONF}" || true
  # user
  sed -ri "s|^(\s*user\s+).*$|\1${ADMIN_USER}:${ADMIN_PASS}|g" "${ZOPe_CONF}" || true

  log "patched zope.conf -> http ${HTTP_ADDRESS}:${HTTP_PORT} / zeo ${ZEO_ADDRESS} / user ${ADMIN_USER}:***"
}

log "MODE=${MODE}"
log "HTTP=${HTTP_ADDRESS}:${HTTP_PORT}"
log "ZEO_LISTEN=${ZEO_LISTEN}:${ZEO_PORT}"
log "ZEO_ADDRESS=${ZEO_ADDRESS}"

case "${MODE}" in
  zeo)
    patch_zeo
    exec "${APP_DIR}/bin/zeoserver" fg
    ;;
  instance|fg)
    patch_zeo
    patch_instance
    exec "${APP_DIR}/bin/instance" fg
    ;;
  check)
    patch_zeo
    patch_instance
    echo "OK"
    echo "zeo.conf: ${ZEO_CONF}"
    echo "zope.conf: ${ZOPe_CONF}"
    exit 0
    ;;
  *)
    die "Unknown MODE '${MODE}'. Use: zeo | instance | fg | check"
    ;;
esac
